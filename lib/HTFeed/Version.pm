package HTFeed::Version;

use warnings;
use strict;
use Carp;

use File::Basename;
use Getopt::Long qw(:config pass_through no_ignore_case no_auto_abbrev);

use base qw( Exporter );
our @EXPORT_OK = qw( get_vstring get_full_version_string get_production_ok );

##################################################
#            HTFeed version strings              #
#  This block is generated by make, do not edit  #
##################################################
my ($vstring,$full_version_string,$production_ok) = ('0.0.0','feed-export-0.0.0',0); # HTFEED_VERSION_STRINGS
########## End HTFeed version strings ############

# try git
unless($vstring and $full_version_string and defined $production_ok) {
    _get_version_from_git(\$vstring,\$full_version_string,\$production_ok);
}
# try fs
unless($vstring and $full_version_string and defined $production_ok) {
    _get_version_from_fs(\$vstring,\$full_version_string,\$production_ok);
}
# die by default
unless($vstring and $full_version_string and defined $production_ok) {
    die("feed cannot find it's version");
}

carp "### DEVELOPMENT VERSION ### $full_version_string"
    unless($production_ok);

use version;
print "$vstring \n";
our $VERSION = version->declare($vstring);

sub get_vstring {
    return $vstring;
}

sub get_full_version_string {
    return $full_version_string;
}

sub get_production_ok {
    return $production_ok;
}

sub import{
    my $self = shift;
    my @options = grep(/^:no_getopt$/, @_);

    $self->SUPER::export_to_level(1, $self, grep(!/^:no_getopt$/, @_));
    
    # process --version and --Version command line ops
    unless ($options[0] and $options[0] eq ":no_getopt") {
        my ($short, $long);
        GetOptions ( "version" => \$short, "Version" => \$long );
        _long_version() and exit 0 if ($long);
        _short_version() and exit 0 if ($short);
    }
}

sub _short_version{
    print "Feed, the HathiTrust Ingest System. Feeding the Elephant since 2010.\n";
    print "$VERSION\n";
}

sub _long_version{
    _short_version();
    # convert paths to module names; return all those that are a subclass
    # of the given class
	require HTFeed;
    HTFeed::load_namespaces();
    HTFeed::load_pkgtypes();

    print "\n*** Loaded Namespaces ***\n";
    print join("\n",map {HTFeed::id_desc_info($_)} ( sort( HTFeed::find_subclasses("HTFeed::Namespace") )));
    print "\n*** Loaded PackageTypes ***\n";
    print join("\n",map {HTFeed::id_desc_info($_)} ( sort( HTFeed::find_subclasses("HTFeed::PackageType") )));
    print "\n*** Loaded Stages ***\n";
    print join("\n",sort( HTFeed::find_subclasses("HTFeed::Stage")));
    print "\n";
}

sub _get_version_from_git {
    my ($vstring,$full_version_string,$production_ok) = @_;
    
    my $this_module = __PACKAGE__ . '.pm';
	$this_module =~ s/::/\//g;
    my $path_to_this_module = dirname($INC{$this_module});
    # is git installed?
    if(! system("which git > /dev/null 2>&1")) {
        # are we in a git repo?
        if(! system("cd $path_to_this_module; git status > /dev/null 2>&1")) {
            # get feed description from git
            my $git_string = `cd $path_to_this_module; git describe --tags --long`;
            chomp $git_string;
            _parse_git_string($git_string,$vstring,$full_version_string,$production_ok);
            1;
        }
    }
    
    return;
}

sub _get_version_from_fs {
    my ($vstring,$full_version_string,$production_ok) = @_;

    # don't 'use' Config, we need to be able to compile without it
    require HTFeed::Config;
    HTFeed::Config->import(qw(get_config));

    my $feed_bin_dir = get_config('feed_bin');
    
    if(defined $feed_bin_dir) {
        my $version_file = $feed_bin_dir . '/rdist.timestamp';
        if (-e $version_file){
            open(my $fh, '<', $version_file);
            my $version_file_contents = <$fh>;
            close $fh;
            chomp $version_file_contents;
            {
                $version_file_contents =~ /^feed_(v[0-9\.]+)$/;
                $$vstring = $1;
            }
            if($$vstring) {
                $$full_version_string = $version_file_contents;
                $$production_ok = 1;
            }
        }
    }

    return;
}

=synopsis

_parse_git_string($git_string,\$vstring,\$full_version_string,\$production_ok)

=cut
sub _parse_git_string {
    my ($git_string,$vstring,$full_version_string,$production_ok) = @_;
    $git_string =~ /^feed_v # required prefix
                    (\d{1,3}) # major version
                    \.(\d{1,3}) # minor version
                    \.?((?<=\.)\d{1,3}|(?<!\.)) # optional tertiary version
                    _?((?<=_)[0-9a-zA-Z\._]+|(?<!_)) # optional development tag
                    -(\d+) # commits since tag
                    -(g[0-9a-f]+) # commit id
                    -?((?<=-)dirty|(?<!-))? # optional dirty flag
                    $/x;
    my ($maj,$min,$ter,$dev_tag,$commit_count,$commit_id,$dirty) = ($1,$2,$3,$4,$5,$6,$7);
    
    if(defined $maj and defined $min and defined $commit_count and $commit_id){
        $$vstring = "v$maj.$min";
        $$vstring .= ".$ter" if(defined $ter);

        # dev
        if($dev_tag) {
            $$vstring .= "_$commit_count";
            $$full_version_string = $git_string;
            $$production_ok = 0;
            return;
        }
        # production
        if(!$dev_tag and $commit_count == 0 and !$dirty) {
            $$full_version_string = 'feed_'.$$vstring;
            $$production_ok = 1;
            return;
        } else {
            croak("Tainted code running under deployment version tag: $git_string, apply dev tag to run dev version");
        }
    }
    
    # invalid string
    croak("Error reading version number from Git, invalid string: $git_string");
}


1;
__END__

=head1 NAME

HTFeed::Version - Version management

=head1 SYNOPSIS

Version.pm provides methods for Feed tool version maintenence

=head1 DESCRIPTION

Can be used in a pl to enable -version and -Version flags

In script.pl:
use HTFeed::Version;

At command line:
script.pl -version
script.pl --Version

INSERT_UNIVERSITY_OF_MICHIGAN_COPYRIGHT_INFO_HERE

=cut
