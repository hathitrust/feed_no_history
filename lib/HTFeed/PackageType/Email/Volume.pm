package HTFeed::PackageType::Email::Volume;

use warnings;
use strict;
use Carp;
use File::Find;
use HTFeed::Config qw(get_config);
use File::Basename qw(basename dirname);
use Log::Log4perl qw(get_logger);
use File::Path qw(remove_tree);
use base qw(HTFeed::Volume);

# complain if no contents are found in a dir

sub reset {
    my $self = shift;
    delete $self->{manifest};
    delete $self->{ead};
    delete $self->{source_premis};
    $self->SUPER::reset;
}

sub check_contents {
    my $self = shift;
    my $dir = shift;

    opendir(DIR, "$dir") || die "can't open dir $dir: $!\n";
     if(scalar(grep( !/^\.\.?$/, readdir(DIR)) == 0)){
        get_logger()->error("$dir is empty");
        return 0;
    } else {
        return 1;
    }
}

# determine submission directories in main staging area
sub get_submissions {
	my $self = shift;
    my $path = $self->get_staging_directory();
	my @submissions;
    opendir(DIR, $path) || die "Can't open dir $path: $!\n";
    while (my $dir = readdir(DIR)) {
        next if ($dir =~ m/^\./);
        next unless(-d "$path/$dir");
        push(@submissions, $dir);
    }
    closedir(DIR);

	return @submissions;
}

sub get_fetch_directory {
	return get_config('staging'=>'fetch');
}

sub get_all_content_dirs {
    my $self = shift;
	my $dir = $self->get_staging_directory();
	my @dirs;

	opendir(DIR, $dir) || die "Can't open dir $dir: $!\n";
	while (my $file = readdir(DIR)) {
        next if ($file =~ m/^\./);
		next unless (-d "$dir/$file");
		push (@dirs, $file);
    }
	closedir(DIR);
    return @dirs;
}

sub get_all_directory_files {
    my $self = shift;

	$self->{directory_files} = [];
	my $stagedir = $self->get_staging_directory();
	opendir(my $dh,$stagedir) or croak("Can't opendir $stagedir: $!");
	foreach my $file (readdir $dh) {
		next if($file =~ /^\.+$/);

		if (-d "$stagedir/$file") {

			opendir(my $subdir, "$stagedir/$file") or croak("Can't opendir $file: $!");
			foreach my $item(readdir $subdir){
    			# process sub level, ignore ., ..
    			push(@{ $self->{directory_files} },$item) unless $item =~ /^\.+$/;
			}
			closedir($subdir) or croak("Can't closedir $file: $!");

		} else {
    		# process main level, ignore ., ..
    		push(@{ $self->{directory_files} },$file) unless $file =~ /^\.+$/;
		}	
	}
	closedir($dh) or croak("Can't closedir $stagedir: $!");
	@{ $self->{directory_files} } = sort( @{ $self->{directory_files} } );

	return $self->{directory_files};
}

sub get_mbox_files {
	my $self = shift;
	my $path = $self->get_staging_directory();
	my @mboxdirs;
	my @mboxes;

    if(not defined $self->{mboxes}) {

        opendir(DIR, $path) || die "Can't open dir $path: $!\n";
        while (my $dir = readdir(DIR)) {

            next if ($dir =~ m/^\./);
            next unless(-d "$path/$dir");
            push(@mboxdirs, $dir)
        }
        closedir(DIR);

        foreach my $mboxdir(@mboxdirs){

            $mboxdir = "$path/$mboxdir";
            opendir(MBOX, $mboxdir) || die "Can't open dir $mboxdir: $!\n";
            while(my $mbox = readdir(MBOX)) {
                next unless ($mbox =~ /mbox$/);

                push(@mboxes,"$mboxdir/$mbox");
            }
        }
        close(MBOX);

        $self->{mboxes} = [sort @mboxes];
    }

	return @{$self->{mboxes}};
}

sub get_mbox_files_by_sub {
	my $self = shift;
	my $sub = shift;

    if(not defined $self->{mboxes_by_sub}{$sub}) {

        my $path = $self->get_staging_directory();
        my $mboxdir = "$path/$sub";
        my @mboxes;

        opendir(MBOX, $mboxdir) || warn("Can't open dir $mboxdir");
        while(my $mbox = readdir(MBOX)) {
            next unless($mbox =~ /mbox$/);
            push(@mboxes,"$mboxdir/$mbox");
        }
        close(MBOX);

        $self->{mboxes_by_sub}{$sub} = [sort @mboxes]
    }

	return @{$self->{mboxes_by_sub}{$sub}};
}

# returns hash of supplementary files and submission path
sub get_supplementary_files_by_sub {
	my $self = shift;
	my $sub = shift;

	my $path = $self->get_staging_directory();
	my $dir = "$path/$sub";

    my @files = ();

    if(not defined $self->{supplements_by_sub}{$sub}) {

        opendir(DIRECTORY, $dir) || warn("Can't open dir $dir");
        while(my $file = readdir(DIRECTORY)) {
            next unless($file =~ /zip$/ || $file =~ /pst$/);
            push(@files,"$dir/$file");
        }
        close(MBOX);

        $self->{supplements_by_sub}{$sub} = [@files];
    }

	return @{$self->{supplements_by_sub}{$sub}};
}

# returns a hash of attachments and their respective mbox path
sub get_attachments_by_mbox {
	my $self = shift;
	my $sub = shift;
	my $mbox = shift;
	my $basedir = $self->get_staging_directory();
	my $path = "$basedir/$sub/$mbox";

	my %attachments = ();

	#check if there's an associated dir
    my $attach_dir = "$path" . "_attachments";

    next unless(-d $attach_dir);

	# if there is, get the attachments
    opendir(DIR, $attach_dir) || die "Can't open dir $attach_dir: $!\n";
    foreach my $att (readdir(DIR)) {
            next if $att =~ /\.+$/;
        $attachments{$att} = $attach_dir;
    }
    closedir(DIR);
	return %attachments;
}

sub get_attachment_files {
	my $self = shift;
	my $path = $self->get_staging_directory();
	my %attachments;

	my $filegroups = $self->get_file_groups();
	while ( my ( $filegroup_name, $filegroup) = each( %{$filegroups} ) ) {
		if($filegroup_name eq "mbox") {
            foreach my $full_mbox_path ($self->get_mbox_files()) {

				# get the attachments associated with each mbox
				my $fgroup = "attachments";
	            my $attach_dir = "$full_mbox_path" . "_attachments";

				next unless(-d $attach_dir);
	
				opendir(DIR, $attach_dir) || die "Can't open dir $attach_dir: $!\n";
	            foreach my $att (readdir(DIR)) {
					next if $att =~ /\.+$/;
	                $attachments{$att} = $attach_dir;
	            }
	            closedir(DIR);
			}
		}
	}
	return %attachments;
}

sub get_supplementary_files {
    my $self = shift;
    my $path = $self->get_staging_directory();
    my @subdirs;
    my @files;

    if(not defined $self->{supplementary_files}) {

        opendir(DIR, $path) || die "Can't open dir $path: $!\n";
        while (my $dir = readdir(DIR)) {
            next if ($dir =~ m/^\./);
            next unless(-d "$path/$dir");
            push(@subdirs, $dir)
        }
        closedir(DIR);

        foreach my $subdir(@subdirs){
            $subdir = "$path/$subdir";

            opendir(SUB, $subdir) || die "Can't open dir $subdir: $!\n";
            while(my $file = readdir(SUB)) {

                next unless($file =~ /\.zip$/ || $file =~ /\.pst$/);

                push(@files,"$subdir/$file");
            }
        }
        close(SUB);

        $self->{supplementary_files} = [@files];
    }

	return @{$self->{supplementary_files}};
}

sub get_metadata_files {
	my $self = shift;

	my @files = qw(ead manifest source_premis);
	foreach my $file(@files){
		my $sub = "get_" . "$file";
		$self->$sub();
    }
	return;
}

sub get_ead {
	my $self = shift;

	if(not defined $self->{ead}) {
        my $ead = $self->{nspkg}->get('ead');

        foreach my $file ( @{ $self->get_all_directory_files() }) {

            if($file =~ $ead) {
                if(not defined $self->{ead}) {
                    $self->{ead} = $file;
                } else {
                    croak("Two or more files match ead file RE $ead: $self->{ead} and $file");
                }
            }
        }
    }
	return $self->{ead};
}

sub get_manifest {
	my $self = shift;

	if(not defined $self->{manifest}) {
        my $manifest_pattern = $self->{nspkg}->get('manifest');
        my $staging_directory = $self->get_staging_directory();

        foreach my $file ( @{ $self->get_all_directory_files() }) {
            if($file =~ $manifest_pattern) {

                if(not defined $self->{manifest}) {
                    $self->{manifest} = "$staging_directory/$file";
                } else {
                    croak("Two or more files match ead file RE $manifest_pattern: $self->{manifest} and $file");
                }
            }
        }
        croak("Can't find manifest matching $manifest_pattern") unless defined $self->{manifest};
    }
	return $self->{manifest};
}

sub get_source_premis {

	my $self = shift;

	if(not defined $self->{source_premis}) {
        my $src = $self->{nspkg}->get('source_premis');

        foreach my $file ( @{ $self->get_all_directory_files() }) {
            if($file =~ $src) {
                if(not defined $self->{source_premis}) {
                    $self->{source_premis} = $file;
                } else {
                    croak("Two or more files match ead file RE $src: $self->{source_premis} and $file");
                }
            }
        }
    }
	return $self->{source_premis};
}

sub get_all_content_files {
	my $self = shift;

	my @content_files = ();

    push( @content_files, map { basename($_) } ($self->get_mbox_files()));

	# get attachment files
	my %attachments = $self->get_attachment_files();

	while ( my ($att, $dir) = each(%attachments) ) {
        push (@content_files, $att);
    }

	# get supplementary files
    push( @content_files, map { basename($_) } ($self->get_supplementary_files()));

	return @content_files;
}

sub get_manifest_path {
	my $self = shift;

	my $staging_path = get_config('staging' => 'ingest');
	my $objid = $self->get_objid();
	my $manifest_path = "$staging_path/$objid.manifest.xml";

	return $manifest_path;
}

sub get_preingest_directory {
    return;
}

sub get_fetch_location {
    my $self = shift;
    my $staging_dir = $self->get_fetch_directory();
    return "$staging_dir/" . $self;
	return;
}

sub get_file_count {
    my $self = shift;
	my @files = $self->get_all_content_files();
    return scalar(@files);
}

# horrible hacks depending on mboxes always being in the same order..
sub get_zip_for_mbox {

    my $self = shift;
    my $wanted_mbox = shift;

    my $zipcount = 0;

    my @mboxes = $self->get_mbox_files();
    push(@mboxes,$self->get_supplementary_files());
    @mboxes = sort(@mboxes);

    foreach my $mbox (@mboxes) {
        $zipcount++;
        if($wanted_mbox eq $mbox) {
            return sprintf("%08d.zip",$zipcount);
        }
    }

    # not found..
    return undef;
}

sub get_mbox_for_zip {
    my $self = shift;
    my $wanted_zip = shift;
    if($wanted_zip =~ /0*(\d+).zip/) {
        $wanted_zip = $1;
        my @mboxes = $self->get_mbox_files();
        push(@mboxes,$self->get_supplementary_files());
        @mboxes = sort(@mboxes);
        my $zipcount = 0;

        foreach my $mbox (@mboxes) {
            $zipcount++;
            if($wanted_zip eq $zipcount) {
                return $mbox;
            }
        }
        return undef;

    } else {
        return undef;
    }
}

sub get_supplement_for_mbox {

    my $self = shift;
    my $mbox = shift;

    $mbox =~ qr#/?([^/]+)(-bhl_[0-9a-f]{8})?.mbox#;
    my $common_tag = $1;

    my @supplements = $self->get_supplementary_files();
    foreach my $supplement (@supplements) {
        if($supplement =~ /$common_tag\.pst$/) {
            return $supplement;
        }
    }

    return ;
}

sub get_manifest_xpc {
    my $self = shift;

    if(not defined $self->{manifest_xpc}) {
        my $manifest = $self->get_manifest();
        return unless defined $manifest;
        $self->{manifest_xpc} = $self->_parse_xpc($manifest);
    }

    return $self->{manifest_xpc};
}


1;

__END__
