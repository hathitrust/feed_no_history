package HTFeed::PackageType::Email::VolumeValidator;

use warnings;
use strict;
use Log::Log4perl qw(get_logger);
use XML::LibXML;
use List::MoreUtils qw(uniq);
use Carp;
use Digest::MD5;
use Encode;
use HTFeed::XMLNamespaces qw(register_namespaces);
use IO::Pipe;
use PREMIS::Outcome;
use HTFeed::Config qw(get_config);
use File::Basename qw(basename dirname);
use Mail::Mbox::MessageParser;
use base qw(HTFeed::VolumeValidator);

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

	$self->{stages}{validate_file_names}           	= \&_validate_file_names;
    $self->{stages}{validate_filegroups_nonempty}	= \&_validate_filegroups;
	$self->{stages}{validate_mbox}					= \&_validate_mbox;
	$self->{stages}{validate_checksums}				= \&_validate_checksums;

    return $self;
}

sub _validate_file_names {
	my $self   = shift;
    my $volume = $self->{volume};
	my $path = $volume->get_staging_directory();

	my $valid_file_pattern = $volume->get_nspkg()->get('valid_file_pattern');
    my @bad                = grep (
        { !/$valid_file_pattern/ } @{ $volume->get_all_directory_files() } );

    foreach my $file (@bad) {

		print "$file\n";

		# ignore dirs (ie submission containers)
		next if(-d "$path/$file");
        $self->set_error(
            "BadFilename",
            field => 'filename',
            file  => $file
        );
    }
    return;
}

sub _validate_filegroups {
  my $self   = shift;
  my $volume = $self->{volume};
  my $path = $volume->get_staging_directory();

  my @contents;

  my $filegroups = $volume->get_file_groups();
  while ( my ( $filegroup_name, $filegroup ) = each( %{$filegroups} ) ) {

    get_logger()->info("validating nonempty filegroup $filegroup_name");
    my $filecount = scalar( @{ $filegroup->get_filenames() } );

    # check dirs for mbox
    if ($filegroup_name eq 'mbox') {

      my @submissions = $volume->get_submissions();
      foreach my $sub(@submissions){

        opendir(DIR,"$path/$sub") or die "Can't open directory $sub $!\n";

        while (my $file = readdir(DIR)) {
          next if ($file =~ m/^\./);
          push @contents, $file;
        }

        close(DIR);

        #warn if sub is empty
        if(scalar @contents eq 0){
          $self->set_error("MissingFile", detail => "Submission directory $sub does not contain any content files");
        }

        @contents=(); #initialize for next sub
      }

      next;

    } else {
      # check other file groups
      if ( !$filecount and $filegroup->get_required() ) {
        $self->set_error( "BadFilegroup", filegroup => $filegroup );
      }
    }
  }

  # check for multiple non-content files
  $volume->get_metadata_files();

  return;
}

# check that mbox files are what they claim to be
sub _validate_mbox {
	my $self = shift;
	my $volume = $self->{volume};

	my @subs = $volume->get_submissions();

	foreach my $sub(@subs){

        foreach my $mbox ($volume->get_mbox_files_by_sub($sub)) {
			my $folder_reader = new Mail::Mbox::MessageParser({
    	        'file_name' => $mbox,
    	        'enable_grep' => 1,
    	        'enable_cache' => 0,
    	    });

    	    #does $file fail MessageParser?
    	    if(! ref $folder_reader) {
    	        $self->set_error('OperationFailed', operation => 'validation', detail => "file $mbox has failed: $folder_reader");
    	    }
    	}
	}
    return;
}

sub _validate_checksums {
	my $self = shift;
	my $volume = $self->{volume};

	my @bad_files = ();

	# get Manifest file
    my $manifest_xpc = $volume->get_manifest_xpc();

    foreach my $mbox ($volume->get_mbox_files()) {

		my $local_checksum = $self->get_checksum($mbox);

        my $basename = basename($mbox);

        my $manifest_checksum = $manifest_xpc->findvalue('//bitstream[@dc.title.filename="' . $basename . '"]/@dc.description.md5checksum');
        unless($local_checksum eq $manifest_checksum){
            $self->set_error(
                "BadChecksum",
                field => 'checksum',
                file => $basename,
                expected => $manifest_checksum,
                actual => $local_checksum,
            );

            push(@bad_files, "$mbox");
        }
    }

	my $outcome;
    if (@bad_files) {
        $outcome = PREMIS::Outcome->new('warning');
        $outcome->add_file_list_detail( "files failed checksum validation",
            "failed", \@bad_files );
    }
    else {
        $outcome = PREMIS::Outcome->new('pass');
    }
    $volume->record_premis_event( 'page_md5_fixity', outcome => $outcome );

	return;
}

sub get_checksum {
	my $self = shift;

	my $file = shift;

	require Digest::MD5;
    open( FILE, $file ) or croak "Can't open '$file': $!";
    binmode(FILE);

    my $digest = Digest::MD5->new->addfile(*FILE)->hexdigest;
    close(FILE);
   	$self->{'attrs'}{'CHECKSUM'}     = $digest;
}

1;

__END__
