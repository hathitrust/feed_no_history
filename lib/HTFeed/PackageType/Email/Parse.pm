package HTFeed::PackageType::Email::Parse;

use strict;
use warnings;
use base qw(HTFeed::Stage);
use HTFeed::Config qw(get_config);
use File::Basename qw(basename dirname);
use Log::Log4perl qw(get_logger);
use Data::Dumper;
use File::Copy;
use Encode;
use Mail::MboxParser;
use Date::Parse;

# Extract attachments from mbox files


# parse each mbox
sub run{
	my $self = shift;
	my $volume =  $self->{volume};
	my $barcode = $volume->get_objid();
	my $dir = $volume->get_staging_directory();

	my @mboxes = $volume->get_mbox_files();

    foreach my $full_mbox_path (@mboxes) {
        $self->parse($full_mbox_path);
    }

	$self->_set_done();
	return;
}

sub parse{
    my $self = shift;
	my $mbox = shift;
	my $messages = 0;

	get_logger()->debug("Processing attachments in $mbox");

	my $filename;
	my $file_handle = new FileHandle($mbox);
	
	my $folder_reader = new Mail::Mbox::MessageParser({
        'file_name' => "$mbox",
        'file_handle' => $file_handle,
        'enable_cache' => 0,
        'enable_grep' => 1,
	});

	# count messages for reporting
	while(!$folder_reader->end_of_file()){
    	my $rawemail = $folder_reader->read_next_email();
		$messages++;
	}

	open(FD,$mbox);

	my $mb = Mail::MboxParser->new("$mbox");	
	my $msg_id;
	my $id;

	# get attachments
    for my $msg ($mb->get_messages) {

        my $date = str2time($msg->header->{date});
        if(not defined $date) {
            $self->set_error("BadField",field => "Date",file=>$mbox . " " . $msg->id,
                detail=>"Can't parse date",actual => $msg->header->{date});
        }

		my $mapping = $msg->get_attachments;
    	for $filename (keys %$mapping) {

			my $attachment_dir = $mbox . "_attachments";			

			my $saved_file = $msg->store_attachment(
				$mapping->{$filename},
				path => $attachment_dir,
				code => sub {
					my ($msg, $n) = @_;
					$filename =~ s/\s/_/g;

					if ($msg->id){
						$id = $msg->id."_$filename";
						$msg_id = $msg->id;
					} else {
						$id = $msg_id."_$filename";					
					}
					return $id;
				},
			);
            utime $date, $date, "$attachment_dir/$saved_file";
    	}
	}

	close (FD);
	
	get_logger()->info("$messages messages found in $mbox");
}

sub stage_info{
    return {success_state => 'parsed', failure_state => 'punted'};
}


1;

__END__
