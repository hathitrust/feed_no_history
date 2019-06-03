package HTFeed::PackageType::Email::Fetch;

use strict;
use warnings;
use base qw(HTFeed::Stage);
use HTFeed::Config qw(get_config);
use Log::Log4perl qw(get_logger);
use HTFeed::Volume;

sub run {
	my $self = shift;
	my $volume = $self->{volume};
	my $barcode = $volume->get_objid();

	my $fetch_dir = get_config('staging' => 'fetch');
	my $source = "$fetch_dir/$barcode";
	my $dest = get_config('staging' => 'ingest');

	if(! -e $dest) {
		mkdir $dest or die ("Can't mkdir $dest $!");
	}

	system("cp -rs '$source' '$dest'");

	$self->_set_done();
	return;
}

sub stage_info{
    return {success_state => 'fetched', failure_state => 'punted'};
}


1;

__END__
