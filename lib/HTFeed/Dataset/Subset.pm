package HTFeed::Dataset::Subset;

use v5.10;
use warnings;
use strict;

use Carp;

use HTFeed::Config;
use YAML::AppConfigFork;
use HTFeed::Dataset::VolumeGroupMaker;
use HTFeed::DBTools;

use File::Pairtree qw(id2ppath s2ppchars);
use File::Path qw(make_path);
use File::Copy;

use base qw(Exporter);
our @EXPORT_OK = qw( update_subsets get_subset_volumegroup get_subset_config );

use Log::Log4perl qw(get_logger);

# updates all subsets
# update_subsets()
#
# update listed subsets
# update_subsets(@subset_names)
sub update_subsets {
    $SIG{CHLD} = 'IGNORE';

    my @subset_list = @_;
    @subset_list = get_subset_config()
        unless (scalar @subset_list);

    foreach my $subset (@subset_list) {
        _update_subset($subset);
    }
}

sub _update_subset {
    my $subset_name = shift;

	# TODO: use global verbose flag to silence this
	print "updating subset: $subset_name\n";

    # get VolumeGroup of volumes this subset is "getting"
    my $getting = get_subset_volumegroup($subset_name);

    # generate path vars
    my $date = date(); # datestamp for id and bib files / links
    my $time = time; # time to append to temp dir for uniqueness

    my $datasets_location = get_config('dataset'=>'path');
    my $target_tree_name  = get_config('dataset'=>'full_set');
    my $trash_dir = get_config('dataset'=>'trash_dir');
    my $link_tree_name = $subset_name;
    my $id_file = "$datasets_location/id/$subset_name-$date.id";
    my $bib_file = "$datasets_location/meta/$subset_name-$date.tar.gz";

    my $target_tree = "$datasets_location/$target_tree_name/obj";
    my $link_tree   = "$datasets_location/$link_tree_name/obj.new.$time";
    my $link_tree_final = "$datasets_location/$link_tree_name/obj";
    my $old_link_tree_final = "$datasets_location/$trash_dir/$link_tree_name.old.$time";
    my $id_file_link = "$link_tree/id";
    my $bib_file_link = "$link_tree/meta.tar.gz";

    # write id file
	# TODO: use global verbose flag to silence this
	print "writing id file: $id_file\n";

	$getting->write_id_file($id_file);

    die "Cannot create $link_tree, directory already exists" if (-e $link_tree);
    die "Cannot link $link_tree, target tree $target_tree missing" unless (-d $target_tree);
    make_path $link_tree or die "Creation of $link_tree failed";

    # write links for id and bib files
    symlink $id_file,$id_file_link or die "Cannot make link $id_file_link";
    symlink $bib_file,$bib_file_link or die "Cannot make link $bib_file_link";

    # scp id file to aleph
    my $whoami = `whoami`;
    chomp($whoami);
    if ($whoami ne 'libadm') {
        warn ("Subset update should be run as libadm. $id_file was not copied to aleph.\n");
    } else {
    	system("scp $id_file aleph\@gimlet:/exlibris/aleph/mdp_meta_transfer/");
    }

    # link volumes
    my $volumes_processed = 0;
    my $total_volumes = $getting->size();

    my $dbh = HTFeed::DBTools->get_dbh();
    my $pid = fork();

    if ($pid) {
        print "Forked process linking $total_volumes volumes\n";
    }
    elsif ($pid == 0) {
        # don't slay the parent's DB handles
        $dbh->{InactiveDestroy} = 1;
        eval{
            while(my $volume = $getting->shift()){
                _symlink_volume($volume,$target_tree,$link_tree);
                $volumes_processed++;
                #print " $volumes_processed"
                #    unless($volumes_processed % 50000);
            }
        };
        if($@){
            die qq(updating $subset_name failed: $@);
        }

        # pivot new set into place
        if(-e $link_tree_final){
            say 'moving old link tree out';
            move($link_tree_final,$old_link_tree_final);
            # start removal of old tree
            system("nohup rm -rf $old_link_tree_final >& /dev/null &");
        }
        say "moving new link tree in";
        move($link_tree,$link_tree_final);
        exit 0; # End child thread
    }
    else { # Unable to fork
      die "ERROR: Could not fork new process: $!";
    }
}

# make symlink from subset pairtree to fullset pairtree
sub _symlink_volume {
    my ($volume,$target_tree,$link_tree) = @_;

    my $ns = $volume->get_namespace();
    my $objid = $volume->get_objid();

    die "can't make subset symlink for $ns.$objid, missing parameters"
        unless ($ns and $objid and $target_tree and $link_tree);

    my ($path,$pt_objid);
    {
        my $pairtree_path = id2ppath($objid);
        chop $pairtree_path; # remove extra '/'
        $pt_objid = s2ppchars($objid);
        $path = "$ns/$pairtree_path";
    }

    my $target = "$target_tree/$path/$pt_objid";
    my $link = "$link_tree/$path/$pt_objid";
    my $link_path = "$link_tree/$path";

    # check that target exists
    die "Target $target missing" unless(-d $target);

    # make link dir
    unless(-d $link_path){
        make_path $link_path or die "Cannot make path $link_path";
    }
    # link
    symlink $target,$link or die "Cannot make link $link";
}

# get_subset_volumegroup($subset_name)
# returns VolumeGroup for subset $subset_name
# Volumes that should be in subset being created
sub get_subset_volumegroup {
    my $subset_name = shift;
    my $config = get_subset_config($subset_name);
    croak "Could not update generate volume group for $subset_name, configuration not found"
        unless ($config);

    return HTFeed::Dataset::VolumeGroupMaker::get_volumes(%{$config});
}

# get_subset_volumegroup_FROM_DISK($subset_name)
# returns VolumeGroup for subset $subset_name
# Volumes that are in subset on disk
## TODO: Rename and possibly move this
sub get_subset_volumegroup_FROM_DISK {
    my $subset_name = shift;
    my $id_path = get_config('dataset'=>'path') . "/$subset_name/obj/id";
    open(my $fh, '<', $id_path) or die "$id_path does not exist";
    my @ids = <$fh>;
    close $fh;
    map { chomp } @ids;
        
    my $vg = HTFeed::VolumeGroup->new('htids'=>\@ids);
    return $vg;
}

# get_subset_config() # list subset names
# get_subset_config($subset_name) # get config for $subset_name
my $subset_config;
sub get_subset_config {
    my $subset_name = shift;

    unless ($subset_config) {
        my $datasets_dir = get_config('dataset'=>'path');
        my $conf_dir = "$datasets_dir/conf";

        my $filename;
        eval{
            foreach my $config_file (sort(glob("$conf_dir/*.yml"))){
                $filename = $config_file; # save filename in case we die
                if($subset_config){
                    $subset_config->merge(file => $config_file);
                } else {
                    $subset_config = YAML::AppConfigFork->new(file => $config_file);
                }
            }
        };
        if ($@) { $subset_config = undef; die ("loading $filename failed: $@"); }
        unless (defined $subset_config) { croak ("no dataset config files found at $conf_dir/"); }
    }

    return ($subset_config->config_keys()) unless ($subset_name);
    return $subset_config->get($subset_name);
}

# make id list
#
## _link($setname,set_dir,$date)
#sub _link {
#    my ($setname,$set_dir,$date)
#    # link id list
#    symlink "../../id/$setname-$date.gz"
#    # link bib data
#}

sub date {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $year += 1900;
    $mon ++;
    return sprintf('%04d%02d%02d-%02d%02d%02d', $year,$mon,$mday,$hour,$min,$sec);
}

1;

__END__
