package HTFeed::Dataset::Stage::UnpackFileGroup;

use warnings;
use strict;

use base qw(HTFeed::Stage::Unpack);
use HTFeed::Config;
use Log::Log4perl qw(get_logger);

sub run{
    my $self = shift;
    # make staging directories
    $self->SUPER::run();
    my $volume = $self->{volume};

    my $zipfile = $volume->get_repository_zip_path();

    # check that mets files exists (we can't select ocr files without it)
    unless (-e $volume->get_repository_mets_path()){
        $self->set_error('MissingFile',file=>$volume->get_repository_mets_path());
        return;
    }
    
    # check that file exists
    if (-e $zipfile){
        # unpack only .txt files
        $self->unzip_file($zipfile,$volume->get_staging_directory(),'*.txt') or return;
    }
    else{
        $self->set_error('MissingFile',file=>$zipfile);
        return;
    }

    # make sure list of files extracted matches list of files expected
    my $expected = $volume->get_file_groups()->{ocr}->{files};
    # WARNING: get_all_directory_files memoizes its data, don't rely on it more than once if the staging dir contents may have changed
    my $found = $volume->get_all_directory_files;
    
    # compare found and expected
    my @missing; # @expected - @found # fatal error if non empty
    my @extra;   # @found - @expected # items in this array will be deleted from fs
    {
        my %found = map {$_ => 1} @{$found};
        my %expected =  map {$_ => 1} @{$expected};

        foreach my $fnd (keys %found){ push @extra, $fnd unless($expected{$fnd}) };
        foreach my $exp (keys %expected){ push @missing, $exp unless($found{$exp}) };
    }
    
    # missing files is a fatal error
    #join (q(,), @missing) . " files missing from $htid" if ($#missing > -1);
    if ($#missing > -1){
        $self->set_error('MissingFile',file=>join(q(,),@missing));
        return;
    }

    # delete any .txt files that aren't ocr
    foreach my $extra_file (@extra){
        get_logger->trace("Removing extra file $extra_file");
        
        my $pathname = get_config('staging'=>'ingest') . "/$extra_file";
        unlink $pathname;
    }    

    $self->_set_done();
    return $self->succeeded();
}

sub stage_info{
    return {success_state => 'unpacked', failure_state => ''};
}

sub clean_failure{
    my $self = shift;
    return $self->{volume}->clean_unpacked_object();
}

1;

__END__
