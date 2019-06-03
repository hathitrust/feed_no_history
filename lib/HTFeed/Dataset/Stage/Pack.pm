package HTFeed::Dataset::Stage::Pack;

use base qw(HTFeed::Stage::Pack);

use Log::Log4perl qw(get_logger);
use HTFeed::Config;

sub run{
    my $self = shift;
    my $volume = $self->{volume};
    
    my $pt_objid = $volume->get_pt_objid();
    my $stage = $volume->get_staging_directory();

    # Make a temporary staging directory
    my $zipfile_stage = get_config('staging'=>'zipfile');
    mkdir($zipfile_stage);
    mkdir("$zipfile_stage/$pt_objid");
    
    # zip
    $stage = get_config('staging'=>'ingest');
    my $zip_path = $volume->get_zip_path();
    $self->zip($stage,q(),$zip_path,$pt_objid) or return;
    
    $self->_set_done();
    return $self->succeeded();
}

1;

__END__
