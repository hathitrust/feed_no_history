package HTFeed::Dataset::RightsDB;

=description
    Access rights DB    
=cut

use warnings;
use strict;
use Carp;

use HTFeed::Config;
use base qw(HTFeed::DBTools);

####our @EXPORT = qw(get_rights get_volumes);
##our @EXPORT_OK = qw(get_volumes);

use Readonly;

####
# The following are aliases for rights table codes. The hash keys can be used in config files to identify rights codes allowed or disallowed in datasets
#
# %attributes and %sources should be updated as more values are added to those tables
####

# pd_us: all attrs that are public domain in US
# pdworld: all attrs that are public domain worldwide (or ps_ud without 9)
Readonly::Hash my %attributes => {pd_us => [1,7,9,10,11,12,13,14,15,17,20,21,22,23,24,25], pd_world => [1,7,10,11,12,13,14,15,17,20,21,22,23,24,25]};
# text/non_google_text are sources that (1) are actually books, not just image collections and (2) don't have special legal entanglements making them full view, but disallowed for distribution
# google is just google sources volumes
Readonly::Hash my %sources => {text => [1,2,4,5,8..29], non_google_text => [2,4,5,8..29], google => [1]};
# not yet enabled, will replace sources
Readonly::Hash my %profiles => {open => [1], google => [2]};
# what it says, currently the only reason code we are interested in asa dataset param
Readonly::Hash my %reasons => {google_full_view => [12]};


=item get_volumes

return array of (namespace,id) pairs matching rights criteria

=synopsis

use HTFeed::Dataset::RightsDB;

get_volumes(
    source => 'non_google_text',
    ns => ['mdp','uc1'],
    attributes => 'pd_us',
)

get_volumes(
    source_not => [1,3,6,7,8],
    ns_not => ['mdp','uc1'],
    attributes_not => [1,7,9,14,15],
)

=cut

sub get_volumes {
    my $where = _where(@_);
    my $q = "SELECT namespace, id FROM rights_current WHERE $where;"; 

    my $sth = HTFeed::DBTools::get_dbh()->prepare($q);
    $sth->execute();

    my $ns_objids = $sth->fetchall_arrayref();
	return HTFeed::VolumeGroup->new(ns_objids=>$ns_objids);
}

sub get_fullset_volumegroup {
	return get_volumes(get_config('dataset'=>'full_set_rights'));
}

sub get_fullset_missing_volumegroup {
    my $where = _where(get_config('dataset'=>'full_set_rights'));
    my $q = "SELECT namespace, id FROM ht_rights.rights_current NATURAL LEFT JOIN ht_repository.feed_dataset_tracking WHERE $where AND (version IS NULL OR delete_t IS NOT NULL)";
	
    my $sth = HTFeed::DBTools::get_dbh()->prepare($q);
    $sth->execute();

    my $ns_objids = $sth->fetchall_arrayref();
	return HTFeed::VolumeGroup->new(ns_objids=>$ns_objids);
}

=item get_bad_volumes

return array of (namespace,id) pairs in full_set that DO NOT match rights criteria

=cut

sub get_bad_volumes {
    my $where = _where(get_config('dataset'=>'full_set_rights'));
    $where = "feed_dataset_tracking.delete_t IS NULL AND NOT ($where)";
    # rm files missing from rights db
    #$where = "feed_dataset_tracking.delete_t IS NULL AND ((NOT ($where)) OR attr IS NULL)";
    my $q = "SELECT namespace, id FROM feed_dataset_tracking NATURAL LEFT JOIN rights_current WHERE $where;"; 

    my $sth = HTFeed::DBTools::get_dbh()->prepare($q);
    $sth->execute();

    my $ns_objids = $sth->fetchall_arrayref();
	return HTFeed::VolumeGroup->new(ns_objids=>$ns_objids);
}

sub _where {
    my $args;
    if (($#_ == 0) and (ref $_[0] eq 'HASH')){
        $args = $_[0];
    }
    else{
        $args = {
            source         => undef,
            ns             => undef,
            attributes     => undef,
            reasons        => undef,
            source_not     => undef,
            ns_not         => undef,
            attributes_not => undef,
            reasons_not    => undef,
            profiles       => undef, # doesn't work yet
            profiles_not   => undef, # doesn't work yet
            @_
        };
    }

    my $source          = $args->{source};
    # get predefined source group
    if(defined $source and !ref($source)){
        $source = _replace_scalar(\%sources,$source,'source');
    }
    my $ns              = $args->{ns};
    my $attributes      = $args->{attributes};
    # get predefined attributes group
    if(defined $attributes and !ref($attributes)){
        $attributes = _replace_scalar(\%attributes,$attributes,'attribute');
    }
    my $reasons         = $args->{reasons};
    # get predefined reasons group
    if(defined $reasons and !ref($reasons)){
        $reasons = _replace_scalar(\%reasons,$reasons,'reasons');
    }
    my $source_not      = $args->{source_not};
    # get predefined !source group
    if(defined $source_not and !ref($source_not)){
        $source_not = _replace_scalar(\%sources,$source_not,'source');
    }
    my $ns_not          = $args->{ns_not};
    my $attributes_not  = $args->{attributes_not};
    # get predefined !attributes group
    if(defined $attributes_not and !ref($attributes_not)){
        $attributes_not = _replace_scalar(\%attributes,$attributes_not,'attribute');
    }
    my $reasons_not     = $args->{reasons_not};
    # get predefined reasons_not group
    if(defined $reasons_not and !ref($reasons_not)){
        $reasons_not = _replace_scalar(\%reasons,$reasons_not,'reasons_not');
    }

    my @where_clauses;
    
    # attributes
    my $where_attributes = _make_where_where_not($attributes,$attributes_not,'attr');
    push @where_clauses, $where_attributes if $where_attributes;

    # source
    my $where_source = _make_where_where_not($source,$source_not,'source');
    push @where_clauses, $where_source if $where_source;

    # ns
    my $where_ns = _make_where_where_not($ns,$ns_not,'namespace');
    push @where_clauses, $where_ns if $where_ns;
    
    # reasons
    my $where_reasons = _make_where_where_not($reasons,$reasons_not,'reason');
    push @where_clauses, $where_reasons if $where_reasons;
    
    my $where = join(' AND ', @where_clauses);
    
    return $where;
}

=item _replace_scalar(\%choice_hash,$scalar,'name',)
Helper fn for _where to replace aliases for predefined lists with said lists
=synopsys
$attributes = _replace_alias(\%attributes,$attributes,'attribute')
=cut
sub _replace_scalar{
    my $choice_hash = shift;
    my $old_scalar = shift;
    my $field_name = shift;

    my $new_array = $choice_hash->{$old_scalar};
    if(ref $new_array){
        return $new_array;
    }
    
    croak "bad $field_name group";
}

=item _make_where_where_not
    combine a list of desired and excluded attributes into sql WHERE syntax
=cut
sub _make_where_where_not{
    my ($attrs,$attrs_not,$attr_name) = @_;

    if ($#$attrs == '-1' and $#$attrs_not == -1) {
        return;
    }
    elsif ($#$attrs == '-1' and $#$attrs_not > -1) {
        return "$attr_name NOT IN ('". join(q(','),@{$attrs_not}) ."')";
    }
    elsif ($#$attrs > '-1' and $#$attrs_not == -1) {
        return "$attr_name IN ('". join(q(','),@{$attrs}) ."')";
    }
    else {
        croak "Can't have both where and where not for $attr_name";
    }
}

1;

__END__


