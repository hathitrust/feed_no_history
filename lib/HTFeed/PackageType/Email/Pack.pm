package HTFeed::PackageType::Email::Pack;

use strict;
use warnings;
use base qw(HTFeed::Stage::Pack);
use HTFeed::Config qw(get_config);
use File::Path qw(remove_tree);
use Log::Log4perl qw(get_logger);
use File::Basename qw(basename dirname);

sub run {
	my $self = shift;

	my $volume = $self->{volume};
	my $objid = $volume->get_objid();
	my $staging_dir = $volume->get_staging_directory();

    # Make a temporary staging directory
    my $zip_stage = get_config('staging'=>'zip');
    my $zipfile_stage = get_config('staging'=>'zipfile');
    mkdir($zip_stage);
    mkdir($zipfile_stage);
    mkdir("$zip_stage/$objid");
    mkdir("$zipfile_stage/$objid");

    # zip all mboxes and psts
    my @mboxes = $volume->get_mbox_files();
    push(@mboxes,$volume->get_supplementary_files());
    @mboxes = sort(@mboxes);
       
    foreach my $full_mbox_path (@mboxes) { 
        my $mbox = basename($full_mbox_path);
        my $mboxdir = dirname($full_mbox_path);
        mkdir($zip_stage);
        mkdir("$zip_stage/$objid");

   		if(! -e $full_mbox_path) {
    		$self->set_error('MissingFile',file => $full_mbox_path);
    	}

        my $base_mboxdir = basename($mboxdir);
		my $attachdir = "$mbox" . "_attachments";

        mkdir("$zip_stage/$objid/$base_mboxdir");

        # link mbox
		if(!symlink($full_mbox_path,"$zip_stage/$objid/$base_mboxdir/$mbox")) {
    		$self->set_error('OperationFailed',operation=>'symlink',file => $full_mbox_path,detail=>"Symlink to staging directory failed: $!");
    	}

        # link attachments
		if (-d "$mboxdir/$attachdir"
		    and !symlink("$mboxdir/$attachdir","$zip_stage/$objid/$base_mboxdir/$attachdir")) {
    		$self->set_error('OperationFailed',operation=>'symlink',file => "$mboxdir/$attachdir",detail=>"Symlink to staging directory failed: $!");
		}
           
        # zip it... 
        my $zip_file = $self->get_next_zip();
        my $zip_output = "$zipfile_stage/$objid/$zip_file";

        # FIXME: race condition/collision if packaging two simultaneously
        $self->zip($zip_stage,$zip_output,$objid) or return;

        # clean out zip dir
        $self->clean_success();
        $self->clean_always();
        
    }

    $self->_set_done();

    $volume->record_premis_event('zip_compression');

    return;
}

sub get_next_zip {

    my $self = shift;
    if(not defined $self->{zipseq}) {
        $self->{zipseq} = 0;
    }

    $self->{zipseq}++;
    return(sprintf("%08d.zip",$self->{zipseq}));
}

sub zip{
    my $self = shift;
    my ($zip_dir,$zip_path,$objid) = @_;

    get_logger()->trace("Packing $zip_dir/$objid to $zip_path");
    my $zipret = system("cd '$zip_dir'; zip -q -r '$zip_path' '$objid'");

    if($zipret) {
        $self->set_error('OperationFailed',operation=>'zip',detail=>'Creating zip file',exitstatus=>$zipret,file=>$zip_path);
        return;
    } else {

        $zipret = system("cd '$zip_dir'; unzip -qq -t '$zip_path'");

        if($zipret) {
            $self->set_error('OperationFailed',operation=>'unzip',exitstatus=>$zipret,file=>$zip_path,detail=>'Verifying zip file');
            return;
        }
    }

    # success
    get_logger()->trace("Packing $zip_dir/$objid to $zip_path succeeded");
    return 1;
}

1;

__END__
