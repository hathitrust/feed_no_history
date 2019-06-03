package HTFeed::Dataset::VolumeGroupMaker;

use warnings;
use strict;

use Carp;

use HTFeed::Dataset::RightsDB;
use HTFeed::Dataset::SolrBib;
use HTFeed::Dataset::CollectionBuilder;
use HTFeed::Dataset::Workset;

use base qw(HTFeed::DBTools);

sub get_volumes {
    my $args = {
        # criteria for building volume lists
        rights => undef,
        bib_query => undef,
        collection => undef,
        workset => undef,
        @_,
    };
    my $pubmin = $args->{pubmin};
    my $pubmax = $args->{pubmax};
    my $pubdate = $args->{pubdate};
    my $lang008 = $args->{lang008};

    # rights, basic bib queries
    # pd rights implied by presence in feed_dataset_tracking
    my $q = 'SELECT namespace, id FROM feed_dataset_tracking NATURAL LEFT JOIN rights_current WHERE delete_t IS NULL';
    my @params = ();
    $q .= ' AND (' . HTFeed::Dataset::RightsDB::_where($args->{rights}) . ')'
        if ($args->{rights});
    if (defined $pubmin) {
        $q .= ' AND pubdate >= ?';
        push @params, $pubmin;
    }
    if (defined $pubmax) {
        $q .= ' AND pubdate <= ?';
        push @params, $pubmax;
    }
    if (defined $pubdate) {
        $q .= ' AND pubdate = ?';
        push @params, $pubdate;
    }
    if (defined $lang008) {
        $q .= ' AND lang008 = ?';
        push @params, $lang008;
    }

    clock_in('rights');
    my $sth = HTFeed::DBTools::get_dbh()->prepare($q);
    $sth->execute(@params);

    my $ns_objids = $sth->fetchall_arrayref();
	my $vg = HTFeed::VolumeGroup->new(ns_objids=>$ns_objids);
    clock_out('rights');
    print_item_count($vg);

    # solr query
    if ($args->{bib_query}) {
        print "Querying Bib SOLR...\n";
        clock_in('bib');
        my $solr_vg = HTFeed::Dataset::SolrBib::get_volumes($args->{bib_query});
        clock_out('bib');
        print_item_count($solr_vg);

        clock_in('bib_intersect');
        $vg = $vg->intersection($solr_vg);
        clock_out('bib_intersect');
        print_item_count($vg);
    }

    # collection
    if ($args->{collection}) {
        my $coll = $args->{collection};
        print "Fetching collection list: $coll\n";
        my $cb_vg = HTFeed::Dataset::CollectionBuilder::get_volumes($coll);

        clock_in('collection_intersect');
        $vg = $vg->intersection($cb_vg);
        clock_out('collection_intersect');
        print_item_count($vg);
    }
    
    # HTRC workset
    if ($args->{workset}) {
        my $ws = $args->{workset};
        print "Fetching workset list: $ws\n";
        croak "missing author for $ws"
            unless ($args->{author});
        my $ws_vg = HTFeed::Dataset::Workset::get_volumes($ws,$args->{author});

        clock_in('workset_intersect');
        $vg = $vg->intersection($ws_vg);
        clock_out('workset_intersect');
        print_item_count($vg);
    }

    croak "Bad arguments" unless ($vg);

    return $vg;    
}

my %t0;
sub clock_in {
    my $event = shift;
    $t0{$event} = time;
}

sub clock_out {
    my $event = shift;
    my $t1 = time;
    my $t0 = $t0{$event};
    my $dt = $t1 - $t0;
    print "$event: $dt seconds\n";
}

sub print_item_count {
    my $vg = shift;
    my $cnt = $vg->size();
    print "$cnt items\n";
}

1;

__END__

=description

    get a VolumeGroup from a dataset config

=cut
