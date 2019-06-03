package HTFeed::PackageType::Email::Collate;

use warnings;
use strict;
use base qw(HTFeed::Stage::Collate);
use HTFeed::Config qw(get_config);
use File::Path qw(make_path);

# include manifest
# deposit directly in config definied obj_dir
sub run{
    my $self = shift;

    my $volume = $self->{volume};
    my $objid = $volume->get_objid();

    my $object_path = sprintf('%s/%s',get_config('repository'=>'obj_dir'),$objid);

    if(get_config('repository'=>'link_dir') ne get_config('repository'=>'obj_dir')) {
        my $link_parent = sprintf('%s/%s',get_config('repository','link_dir'),,$objid);
        my $link_path = $link_parent . $objid;

        if (-l $link_path){
            $self->set_info('Collating volume that is already in repo');
            $self->{is_repeat} = 1;
            # make sure we have a link
            unless ($object_path = readlink($link_path)){
                # there is no good reason we could have a dir and no link
                $self->set_error('OperationFailed', operation => 'readlink', file => $link_path, detail => "readlink failed: $!") 
                    and return;
            }
        }
        # make dir or error and return
        else{
            # make object path
            make_path($object_path);
            # make link path
            make_path($link_parent);
            # make link
            symlink ($object_path, $link_path)
                or $self->set_error('OperationFailed', operation => 'mkdir', detail => "Could not create dir $link_path") and return;
        }
    } else{ # handle re-ingest detection and dir creation where link_dir==obj_dir
        if(-d $object_path) {
            # this is a re-ingest if the dir already exists, log this
            $self->set_info('Collating volume that is already in repo');
            $self->{is_repeat} = 1;
        } else{
            make_path($object_path)
                or $self->set_error('OperationFailed', operation => 'mkdir', detail => "Could not create dir $object_path") and return;
        }
    }

    my $mets_source = $volume->get_mets_path();
	my $manifest_source = $volume->get_manifest_path();

    # make sure the operation will succeed
    if (-f $mets_source and -f $manifest_source and -d $object_path){
        # move mets, manifest and zip to destination
        system('cp','-f',$mets_source,$object_path)
            and $self->set_error('OperationFailed', operation => 'cp', detail => "cp $mets_source $object_path failed with status: $?");
            
        system('cp','-f',$manifest_source,$object_path)
            and $self->set_error('OperationFailed', operation => 'cp', detail => "cp $manifest_source $object_path failed with status: $?");

        # copy the zip files - FIXME -- how to make sure we got all of them?
        my $zip_directory =  get_config('staging'=>'zipfile');
        foreach my $zip_file (glob("$zip_directory/$objid/*zip")) {
            system('cp','-f',$zip_file,$object_path)
                and $self->set_error('OperationFailed', operation => 'cp', detail => "cp $zip_file $object_path failed with status: $?");
        }

        $self->_set_done();
        return $self->succeeded();
    }
    
    # report any missing files
    my $detail = 'Collate failed, file(s) not found: ';
    $detail .= $mets_source unless(-f $mets_source);
    $detail .= $manifest_source  unless(-f $manifest_source);
    $detail .= $object_path unless(-d $object_path);
    
    $self->set_error('OperationFailed', detail => $detail);
    return;
}

1;

__END__
