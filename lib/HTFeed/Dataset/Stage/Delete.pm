package HTFeed::Dataset::Stage::Delete;

use warnings;
use strict;

use base qw(HTFeed::Stage);

use File::Path qw(remove_tree);

use Log::Log4perl qw(get_logger);
use HTFeed::Config;
use HTFeed::Dataset::Tracking qw(tracking_delete);

sub run{
    my $self = shift;
    my $volume = $self->{volume};
    
    remove_tree($volume->get_dataset_path());
    my $star_path = $volume->get_dataset_path('*');
    `rm $star_path`;
    tracking_delete($volume);

    ## TODO: Sanity checks here

    $self->_set_done();
    return $self->succeeded();
}

sub stage_info{
    return {success_state => 'done', failure_state => ''};
}

1;

__END__
