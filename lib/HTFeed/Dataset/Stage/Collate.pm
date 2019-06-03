package HTFeed::Dataset::Stage::Collate;

use warnings;
use strict;

use base qw(HTFeed::Stage);

use File::Path qw(make_path);
use Log::Log4perl qw(get_logger);
use HTFeed::Dataset::Tracking qw(tracking_add);

sub run{
    my $self = shift;
    my $volume = $self->{volume};
    
    make_path $volume->get_dataset_path;
    
    $self->copy($volume->get_repository_mets_path(), $volume->get_dataset_path(), 'METS') or return;
    $self->copy($volume->get_zip_path(), $volume->get_dataset_path(), 'zip') or return;

	tracking_add($volume);

    $self->_set_done();

    return $self->succeeded();
}

sub stage_info{
    return {success_state => 'done', failure_state => ''};
}

=item copy
    $self->copy($src,$dest)
=cut
sub copy{
    my $self = shift;
    my ($src,$dest,$file_description) = @_;
    
    get_logger()->trace("Copying $src to $dest");    
    my $ret = system('cp','-f',$src,$dest);
    if ($ret){
        $self->set_error('OperationFailed',operation=>'collate',file=>$src,detail=>"Copying $file_description");
        return;
    }

    # success
    get_logger()->trace("Copying $src to $dest succeeded");        
    return 1;
}

sub clean_always{
    my $self = shift;
    $self->{volume}->clean_unpacked_object;
    $self->{volume}->clean_zip;
}

sub clean_success{
    return 1;
}

1;

__END__
