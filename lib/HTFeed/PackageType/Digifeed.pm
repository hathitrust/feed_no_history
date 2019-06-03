package HTFeed::PackageType::Digifeed;

use warnings;
use strict;
use base qw(HTFeed::PackageType::Google);
use HTFeed::XPathValidator qw(:closures);

our $identifier = 'digifeed';

# extract useful info; use loosened reguar expression for getting datetime.
sub extractinfo_nodate {
    my $self = shift;

    $self->_setartist( $self->_findone( "mix", "artist" ) );
    $self->_setdocumentname( $self->_findone( "tiffMeta", "documentName" ) );
}

sub checkdate_loose {
    my $self     = shift;
    my $datetime = shift;

    # allow various separator characters & make seconds optional
    unless ( defined($datetime)
        and $datetime =~
        /^(\d{4}[:\/-]\d\d[:\/-]\d\d[T ]\d\d:\d\d(:\d\d)?)(\+\d\d:\d\d|)(Z|[+-]\d{2}:\d{2})?$/ )
    {
        $self->set_error(
            "BadValue",
            field  => 'datetime',
            actual => $datetime
        );
        return 0;
    }

    # trim
    $datetime = $1;

    # store
    $$self{datetime} = $datetime;
    return 1;
}

our $config = {
    %{$HTFeed::PackageType::Google::config},
    description => 'Google digifeeds',

    validation => {
        'HTFeed::ModuleValidator::JPEG2000_hul' => {
            # Make Make/Model optional.
            'camera' => undef,
            'layers' => v_in( 'codingStyleDefault', 'layers', ['8','25'] ),
            # Just validate that xmp BitsPerSample is present - that's what
            # the original spec said, and what GROOVE 1.0 did
            'colorspace' => sub {
                my $self = shift;

                # check colorspace
                my $xmp_colorSpace = $self->_findone( "xmp", "colorSpace" );
                my $xmp_samplesPerPixel =
                  $self->_findone( "xmp", "samplesPerPixel" );
                my $mix_samplesPerPixel =
                  $self->_findone( "mix", "samplesPerPixel" );
                my $meta_colorSpace = $self->_findone( "jp2Meta", "colorSpace" );
                my $mix_bitsPerSample = $self->_findvalue( "mix", "bitsPerSample" );
                my $xmp_bitsPerSample_grey =
                  $self->_findvalue( "xmp", "bitsPerSample_grey" );
                my $xmp_bitsPerSample_color =
                  $self->_findvalue( "xmp", "bitsPerSample_color" );

                if(not defined $xmp_bitsPerSample_grey
                        and not defined $xmp_bitsPerSample_color) {

                    $self->set_error("MissingField",field=>"xmp_bitsPerSample");

                }

                # Greyscale: 1 sample per pixels, 8 bits per sample
                (
                         ( "1" eq $xmp_colorSpace )
                      && ( "1"         eq $xmp_samplesPerPixel )
                      && ( "1"         eq $mix_samplesPerPixel )
                      && ( "Greyscale" eq $meta_colorSpace )
                      && ( "8"         eq $mix_bitsPerSample )
                  )

                  # sRGB: 3 samples per pixel, each sample 8 bits
                  or ( ( "2" eq $xmp_colorSpace )
                    && ( "3"     eq $xmp_samplesPerPixel )
                    && ( "3"     eq $mix_samplesPerPixel )
                    && ( "sRGB"  eq $meta_colorSpace )
                    && ( "888" eq $mix_bitsPerSample ) )
                  or (
                    $self->set_error(
                        "NotMatchedValue",
                        field  => 'colorspace',
                        actual => {
                            "xmp_colorSpace"          => $xmp_colorSpace,
                            "xmp_samplesPerPixel"     => $xmp_samplesPerPixel,
                            "mix_samplesPerPixel"     => $mix_samplesPerPixel,
                            "jp2Meta_colorSpace"      => $meta_colorSpace,
                            "mix_bitsPerSample"       => $mix_bitsPerSample,
                        }
                    )
                    and return
                  );
            },
            'extract_info' => sub {
                my $self = shift;

                # don't check date time here
                $self->_setartist( $self->_findone( "xmp", "artist" ) );
                $self->_setdocumentname( $self->_findone( "xmp", "documentName" ) );
            },
            'date' => sub { my $self = shift; return checkdate_loose($self,$self->_findone( "xmp", "dateTime" ) ) }
        },
        'HTFeed::ModuleValidator::TIFF_hul' => {
            # Make Make/Model optional.
            'camera' => undef,
            # If the ONLY error is complaining about a bad DateTime separator, don't worry about it.
            # GROOVE 1.0 was passing these through because of a bug in JHOVE 1.0 where it would be 
            # reported as invalid even if it wasn't; so a lot of marginal DateTimes were allowed.
            # Review this after 2011-08-31.
            'status' => sub { 
                my $self = shift;
                my $status = $self->_findone('repInfo','status');
                if($status eq 'Well-Formed and valid') {
                    return 1;
                } elsif($status eq 'Well-Formed, but not valid') {
                    my $error = $self->_findone('repInfo','errors');
                    if($error =~ /^Invalid DateTime separator/) {
                        return 1;
                    }

                }

                $self->set_error("BadValue", field => "status_format", actual => $status, expected => "eq Well-Formed and valid");
                return 0;
            },
            'extract_info' => sub {
                my $self = shift;

                # don't check date time here
                $self->_setartist( $self->_findone( "mix", "artist" ) );
                $self->_setdocumentname(
                    $self->_findone( "tiffMeta", "documentName" ) );
            },
            'date' => sub { my $self = shift; return checkdate_loose($self,$self->_findone( "mix", "dateTime" ) ) },
            'resolution'      => HTFeed::ModuleValidator::TIFF_hul::v_resolution(['600','602','597'])
        }
    }
};

__END__

=pod

This is the package type configuration file for Michigan-digitized material
returned through Google ('digifeeds') which are validated to a slightly looser
spec than Google-digitized material (to be reviewed 2011-08-31).

=head1 SYNOPSIS

use HTFeed::PackageType;

my $pkgtype = new HTFeed::PackageType('faculty_reprints');

=head1 AUTHOR

Aaron Elkiss, University of Michigan, aelkiss@umich.edu

=head1 COPYRIGHT

Copyright (c) 2010 University of Michigan. All rights reserved.  This program
is free software; you can redistribute it and/or modify it under the same terms
as Perl itself.


