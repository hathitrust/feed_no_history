package HTFeed::PackageType::Email::Scan;

use strict;
use warnings;
use base qw(HTFeed::Stage);
use HTFeed::Config qw(get_config);
use Log::Log4perl qw(get_logger);
use Data::Dumper;
use File::Copy;
use Mail::ClamAV qw/:all/;

# scan mbox files for viruses

sub run{
	my $self = shift;

	my $volume =  $self->{volume};
	my $dir = $volume->get_staging_directory();

	opendir (DIR, $dir) || die "can't open dir $dir: $!\n";
    my @mboxes = readdir(DIR);
    closedir(DIR);

	$self->scan(@mboxes);

	$self->_set_done();
	return;
}

sub scan {
	my $self = shift;
	my @mboxes = @_;

	my $volume =  $self->{volume};
    my $dir = $volume->get_staging_directory();

	my $source = get_config('clam_av');

	# set up Mail::ClamAV scan
   	my $c = Mail::ClamAV->new($source) or die "Failed to load db: $Mail::ClamAV::Error";
	$c->build or die "Failed to build engine: $Mail::ClamAV::Error";
    $c->maxreclevel(4);
    $c->maxfiles(20);
    $c->maxfilesize(1024 * 1024 * 20); # 20 megs

	# stats
	my $clean_count = 0;
	my $virus_count = 0;
	my $total_count = 0;
	my @virus_count;

	# scan each $mbox path...
	foreach my $mbox(@mboxes){

		# skip "." & ".."; check in dirs only
		my $mbox = "$dir/$mbox";
		next if($mbox =~ /^\.+$/);
		next unless(-d $mbox);

		# get submission files...
		opendir(DIR, $mbox) || die "Can't open dir $mbox";
		my @files = readdir(DIR);
		foreach my $file(@files){

			# scan actual mbox files here
			next unless($file =~ /.*\.mbox$/);
			get_logger()->debug("scanning $file");
			my $status = $c->scan("$mbox/$file", CL_SCAN_MAIL);
			die "Failed to scan: $status" unless $status;
			if ($status->virus) {
    			get_logger()->warn("Not OK: $status");
				$virus_count++;
				push(@virus_count, $mbox);
			} else {
				$clean_count++;
			}
			$total_count++;
		}
		close(DIR);
	}
	# log results
	if ($virus_count == 0){
		get_logger()->debug("Virus count complete. 0 viruses detected in $clean_count of $total_count scanned files.");
		return 1;
	}else{
		get_logger()->warn("WARNING: Virus detected in $virus_count of $total_count scanned files:\n
		@virus_count\n");
		return 0;
	}
}

sub stage_info{
    return {success_state => 'scanned', failure_state => 'punted'};
}


1;

__END__
