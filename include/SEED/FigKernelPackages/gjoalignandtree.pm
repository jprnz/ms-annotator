package gjoalignandtree;

# This is a SAS component.

#-------------------------------------------------------------------------------
#
#  Order a set of sequences:
#
#    @seqs = order_sequences_by_length( \@seqs, \%opts )
#   \@seqs = order_sequences_by_length( \@seqs, \%opts )
#
#  Write representative seqeunce groups to a file
#
#      write_representative_groups( \%rep, $file )
#
#   @align = trim_align_to_median_ends( \@align, \%opts )
#  \@align = trim_align_to_median_ends( \@align, \%opts )
#
#   print_alignment_as_pseudoclustal( $align, \%opts )
#
#   $prof_rep = representative_for_profile( $align )
#
#    \@trimmed_seq             = extract_with_psiblast( $db, $profile, \%opts )
#  ( \@trimmed_seq, \%report ) = extract_with_psiblast( $db, $profile, \%opts )
#
#  Profile blast against protein database:
#
#   $structured_blast = blastpgp(  $dbfile,  $profilefile, \%options )
#   $structured_blast = blastpgp( \@dbseq,   $profilefile, \%options )
#   $structured_blast = blastpgp(  $dbfile, \@profileseq,  \%options )
#   $structured_blast = blastpgp( \@dbseq,  \@profileseq,  \%options )
#
#  Profile blast against DNA database (PSI-tblastn):
#
#   $structured_blast = blastpgpn(  $dbfile,  $profilefile, \%options )
#   $structured_blast = blastpgpn( \@dbseq,   $profilefile, \%options )
#   $structured_blast = blastpgpn(  $dbfile, \@profileseq,  \%options )
#   $structured_blast = blastpgpn( \@dbseq,  \@profileseq,  \%options )
#
#   print_blast_as_records(  $file, \@queries )
#   print_blast_as_records( \*FH,   \@queries )
#   print_blast_as_records(         \@queries )     # STDOUT
#
#   \@queries = read_blast_from_records(  $file )
#   \@queries = read_blast_from_records( \*FH )
#   \@queries = read_blast_from_records( )          # STDIN
#
#   $exists = verify_db( $db, $type );
#
#-------------------------------------------------------------------------------

use strict;
use SeedAware;
use gjoseqlib;
use gjoparseblast;

#-------------------------------------------------------------------------------
#  Order a set of sequences:
#
#    @seqs = order_sequences_by_length( \@seqs, \%opts )
#   \@seqs = order_sequences_by_length( \@seqs, \%opts )
#
#  Options:
#
#     order  => $key              # increasing (D), decreasing, median_outward,
#                                 #       closest_to_median, closest_to_length
#     length => $prefered_length
#
#-------------------------------------------------------------------------------

sub order_sequences_by_length
{
    my ( $seqs, $opts ) = @_;
    $seqs && ref $seqs eq 'ARRAY' && @$seqs
        or print STDERR "order_sequences_by_length called with invalid sequence list.\n"
           and return wantarray ? () : [];

    $opts = {} if ! ( $opts && ref $opts eq 'HASH' );
    my $order = $opts->{ order } || 'increasing';

    my @seqs = ();
    if    ( $order =~ /^dec/i )
    {
        $opts->{ order } = 'decreaseing';
        @seqs = sort { length( $b->[2] ) <=> length( $a->[2] ) } @$seqs;
    }
    elsif ( $order =~ /^med/i )
    {
        $opts->{ order } = 'median_outward';
        my @seqs0 = sort { length( $a->[2] ) <=> length( $b->[2] ) } @$seqs;
        local $_;
        while ( defined( $_ = shift @seqs0 ) )
        {
            push @seqs, $_;
            push @seqs, pop @seqs0 if @seqs0;
        }
        @seqs = reverse @seqs;
    }
    elsif ( $order =~ /^close/i )
    {
        my $pref_len;
        if ( defined $opts->{ length } )   #  caller supplies preferred length?
        {
            $opts->{ order } = 'closest_to_length';
            $pref_len = $opts->{ length } + 0;
        }
        else                               #  preferred length is median
        {
            $opts->{ order } = 'closest_to_median';
            my @seqs0 = sort { length( $a->[2] ) <=> length( $b->[2] ) } @$seqs;
            my $i = int( @seqs0 / 2 );
            $pref_len = ( @seqs0 % 2 ) ? length( $seqs0[$i]->[2] )
                                       : ( length( $seqs0[$i-1]->[2] ) + length( $seqs0[$i]->[2] ) ) / 2;
        }
 
        @seqs = map  { $_->[0] }
                sort { $a->[1] <=> $b->[1] }  #  closest to preferred first
                map  { [ $_, abs( length( $_->[2] ) - $pref_len ) ] }  # dist from pref?
                @$seqs;
    }
    else
    {
        $opts->{ order } = 'increasing';
        @seqs = sort { length( $a->[2] ) <=> length( $b->[2] ) } @$seqs;
    }

    wantarray ? @seqs : \@seqs;
}


#-------------------------------------------------------------------------------
#  Write representative seqeunce groups to a file
#
#      write_representative_groups( \%rep, $file )
#
#-------------------------------------------------------------------------------

sub  write_representative_groups
{
    my ( $repH, $file ) = @_;
    $repH && (ref $repH eq 'HASH') && keys %$repH
        or print STDERR "write_representative_groups called with invalid rep hash.\n"
           and return;

    my ( $fh, $close ) = &output_file_handle( $file );

    #  Order keys from largest to smallest set, then alphabetical

    my @keys = sort { @{ $repH->{$b} } <=> @{ $repH->{$a} } || lc $a cmp lc $b } keys %$repH;

    foreach ( @keys ) { print $fh join( "\t", ( $_, @{ $repH->{ $_ } } ) ), "\n" }

    close $fh if $close;
}


#-------------------------------------------------------------------------------
#
#   @align = trim_align_to_median_ends( \@align, \%opts )
#  \@align = trim_align_to_median_ends( \@align, \%opts )
#
#  Options:
#
#     begin      => bool   #  Trim start (specifically)
#     end        => bool   #  Trim end (specifically)
#     fract_cov  => fract  #  Fraction of sequences to be covered (D: 0.75)
#
#-------------------------------------------------------------------------------
sub trim_align_to_median_ends
{
    my ( $align, $opts ) = @_;

    $align && ref $align eq 'ARRAY' && @$align
        or print STDERR "trim_align_to_median_ends called with invalid sequence list.\n"
           and return wantarray ? () : [];

    $opts = {} if ! ( $opts && ref $opts eq 'HASH' );
    my $tr_beg = $opts->{ begin } || $opts->{ beg } || $opts->{ start } ? 1 : 0;
    my $tr_end = $opts->{ end } ? 1 : 0;
    $tr_beg = $tr_end = 1 if ! ( $tr_beg || $tr_end );
    my $frac  = $opts->{ fract_cov } || 0.75;

    my( @ngap1, @ngap2);
    foreach my $seq ( @$align )
    {
        my( $b, $e ) = $seq->[2] =~ /^(-*).*[^-](-*)$/;
        push @ngap1, length( $b || '' );
        push @ngap2, length( $e || '' );
    }

    @ngap1 = sort { $a <=> $b } @ngap1;
    @ngap2 = sort { $a <=> $b } @ngap2;

    my $ngap1 = $tr_beg ? $ngap1[ int( @ngap1 * $frac ) ] : 0;
    my $ngap2 = $tr_end ? $ngap2[ int( @ngap2 * $frac ) ] : 0;

    my $ori_len = length( $align->[0]->[2] );
    my $new_len = $ori_len - ( $ngap1 + $ngap2 );
    my @align2 = map { [ @$_[0,1], substr( $_->[2], $ngap1, $new_len ) ] }
                 @$align;

    wantarray ? @align2 : \@align2;
}


#-------------------------------------------------------------------------------
#
#   print_alignment_as_pseudoclustal( $align, \%opts )
#
#   Options:
#
#        file  =>  $filename  #  supply a file name to open and write
#        file  => \*FH        #  supply an open file handle (D = STDOUT)
#        line  =>  $linelen   #  residues per line (D = 60)
#        lower =>  $bool      #  all lower case sequence
#        upper =>  $bool      #  all upper case sequence
#
#-------------------------------------------------------------------------------

sub print_alignment_as_pseudoclustal
{
    my ( $align, $opts ) = @_;
    $align && ref $align eq 'ARRAY' && @$align
        or print STDERR "print_alignment_as_pseudoclustal called with invalid sequence list.\n"
           and return wantarray ? () : [];

    $opts = {} if ! ( $opts && ref $opts eq 'HASH' );
    my $line_len = $opts->{ line } || 60;
    my $case = $opts->{ upper } ?  1 : $opts->{ lower } ? -1 : 0;

    my ( $fh, $close ) = &output_file_handle( $opts->{ file } );

    my $namelen = 0;
    foreach ( @$align ) { $namelen = length $_->[0] if $namelen < length $_->[0] }
    my $fmt = "%-${namelen}s  %s\n";

    my $id;
    my @lines = map { $id = $_->[0]; [ map { sprintf $fmt, $id, $_ }
                                       map { $case < 0 ? lc $_ : $case > 0 ? uc $_ : $_ }  # map sequence only
                                       $_->[2] =~ m/.{1,$line_len}/g
                                     ] }
                @$align;

    my $ngroup = @{ $lines[0] };
    for ( my $i = 0; $i < $ngroup; $i++ )
    {
        foreach ( @lines ) { print $fh $_->[$i] if $_->[$i] }
        print $fh "\n";
    }

    close $fh if $close;
}


#-------------------------------------------------------------------------------
#
#    @seqs = read_pseudoclustal( )              #  D = STDIN
#   \@seqs = read_pseudoclustal( )              #  D = STDIN
#    @seqs = read_pseudoclustal(  $file_name )
#   \@seqs = read_pseudoclustal(  $file_name )
#    @seqs = read_pseudoclustal( \*FH )
#   \@seqs = read_pseudoclustal( \*FH )
#
#-------------------------------------------------------------------------------

sub read_pseudoclustal
{
    my ( $file ) = @_;
    my ( $fh, $close ) = input_file_handle( $file );
    my %seq;
    my @ids;
    while ( <$fh> )
    {
        chomp;
        my ( $id, $data ) = /^(\S+)\s+(\S.*)$/;
        if ( defined $id && defined $data )
        {
            push @ids, $id if ! $seq{ $id };
            $data =~ s/\s+//g;
            push @{ $seq{ $id } }, $data;
        }
    }
    close $fh if $close;

    my @seq = map { [ $_, '', join( '', @{ $seq{ $_ } } ) ] } @ids;
    wantarray ? @seq : \@seq;
}


#-------------------------------------------------------------------------------
#  The profile 'query' sequence:
#
#     1. Minimum terminal gaps
#     2. Longest sequence passing above
#
#    $prof_rep = representative_for_profile( $align )
#-------------------------------------------------------------------------------
sub representative_for_profile
{
    my ( $align ) = @_;
    $align && ref $align eq 'ARRAY' && @$align
        or die "representative_for_profile called with invalid sequence list.\n";

    my ( $r0 ) = map  { $_->[0] }                                      # sequence entry
                 sort { $a->[1] <=> $b->[1] || $b->[2] <=> $a->[2] }   # min terminal gaps, max aas
                 map  { my $tgap = ( $_->[2] =~ /^(-+)/ ? length( $1 ) : 0 )
                                 + ( $_->[2] =~ /(-+)$/ ? length( $1 ) : 0 );
                        my $naa = $_->[2] =~ tr/ACDEFGHIKLMNPQRSTVWYacdefghiklmnpqrstvwy//;
                        [ $_, $tgap, $naa ]
                      }
                 @$align;

    my $rep = [ @$r0 ];             # Make a copy
    $rep->[2] =~ s/[^A-Za-z]+//g;   # Compress to letters

    $rep;
}


#-------------------------------------------------------------------------------
#  Use a profile to extract a region from a sequence. By default, the hsps
#  can be chained together, walking both directions from the highest scoring
#  hsp. Only one region will be extracted per database sequence.
#
#    \@seq             = extract_with_psiblast( $db, $profile, \%opts )
#  ( \@seq, \%report ) = extract_with_psiblast( $db, $profile, \%opts )
#
#     $db      can be $db_file_name      or \@db_seqs
#     $profile can be $profile_file_name or \@profile_seqs
#
#     If supplied as file, profile is pseudoclustal
#
#     Report records:
#
#         [ $sid, $score, $e_value, $slen, $status,
#                 $frac_id, $frac_pos,
#                 $q_uncov_n_term, $q_uncov_c_term,
#                 $s_uncov_n_term, $s_uncov_c_term ]
#
#  Options:
#
#     best_hsp      =>  $bool           #  only report the best hsp (no merging)
#     e_value       =>  $max_e_value    #  maximum blastpgp E-value (D = 0.01)
#     max_e_value   =>  $max_e_value    #  maximum blastpgp E-value (D = 0.01)
#     max_gap       =>  $max_gap_size   #  maximum region unmatched in both query and subject (D = 100)
#     max_offset    =>  $max_offset     #  maximum asymmetry in query and subject gap size (D = 1000)
#                                       #      (i.e., very large insertions are allowed)
#     max_q_uncov   =>  $aa_per_end     #  maximum unmatched query, per end (D = 20)
#     max_q_uncov_c =>  $aa_per_end     #  maximum unmatched query, C-term (D = 20)
#     max_q_uncov_n =>  $aa_per_end     #  maximum unmatched query, N-term (D = 20)
#     min_ident     =>  $frac_ident     #  minimum fraction identity (D =  0.15)
#     min_positive  =>  $frac_positive  #  minimum fraction positive scoring (D = 0.20)
#     min_frac_cov  =>  $frac_cov       #  minimum fraction coverage of query and subject sequence (D = 0.20)
#     min_q_cov     =>  $frac_cov       #  minimum fraction coverage of query sequence (D = 0.50)
#     min_s_cov     =>  $frac_cov       #  minimum fraction coverage of subject sequence (D = 0.01)
#     n_result      =>  $max_results    #  maxiumn restuls returned (D = 1000)
#     n_cpu         =>  $n_thread       #  number of blastpgp threads (D = 2)
#     n_thread      =>  $n_thread       #  number of blastpgp threads (D = 2)
#     one_hsp       =>  $bool           #  only report the best hsp (no merging)
#     query         =>  $q_file_name    #  query sequence file (D = most complete)
#     query         => \@q_seq_entry    #  query sequence (D = most complete)
#     query_used    => \@q_seq_entry    #  output of the query sequence used
#     stderr        =>  $file           #  blastpgp stderr (D = /dev/stderr)
#     strict        =>  $bool           #  only report matches that are unique
#                                       #      and continuous (one hsp)
#
#  If supplied, the query must be identical to a profile sequence, but with no gaps.
#-------------------------------------------------------------------------------

sub extract_with_psiblast
{
    my ( $seqs, $profile, $opts ) = @_;

    $opts && ref $opts eq 'HASH' or $opts = {};

    #  These 3 options set parameters for blastpgp:

    $opts->{ e_value }  ||= $opts->{ max_e_val }  || $opts->{ max_e_value } || 0.01;
    $opts->{ n_result } ||= $opts->{ nresult }    || 1000;
    $opts->{ n_thread } ||= $opts->{ nthread }    || $opts->{ n_cpu } || $opts->{ ncpu } || 4;

    #  These options set values used in this routine:

    my $max_q_uncov_c = $opts->{ max_q_uncov_c  } || $opts->{ max_q_uncov }  || 20;
    my $max_q_uncov_n = $opts->{ max_q_uncov_n  } || $opts->{ max_q_uncov }  || 20;
    my $min_q_cov     = $opts->{ min_q_cov }      || $opts->{ min_frac_cov } || 0.50;
    my $min_s_cov     = $opts->{ min_s_cov }      || $opts->{ min_frac_cov } || 0.01;
    my $min_ident     = $opts->{ min_ident }      || $opts->{ min_identity } || 0.15;
    my $min_pos       = $opts->{ min_positive }                              || 0.20;
    my $strict        = $opts->{ strict }                                    || 0;
    my $best_hsp      = $opts->{ best_hsp }       || $opts->{ one_hsp }      || 0;

    my $blast = blastpgp( $seqs, $profile, $opts );
    $blast && @$blast
        or return wantarray ? ( [], {} ) : [];

    my ( $qid, $qdef, $qlen, $qhits ) = @{ $blast->[0] };

    my @trimmed;
    my %seqs;
    my %report;

    foreach my $sdata ( @$qhits )
    {
        my ( $sid, $sdef, $slen, $hsps ) = @$sdata;

        my $hsp0;
        if ( $hsp0 = $strict ? one_real_hsp( $hsps ) : $best_hsp ? $hsps->[0] : pseudo_hsp( $hsps, $opts ) )
        {
            #  [ scr, exp, p_n, pval, nmat, nid, nsim, ngap, dir, q1, q2, qseq, s1, s2, sseq ]
            #     0    1    2    3     4     5    6     7     8   9   10   11   12  13   14

            my ( $scr, $exp, $nmat, $nid, $npos, $q1, $q2, $s1, $s2, $sseq ) = @$hsp0[ 0, 1, 4, 5, 6, 9, 10, 12, 13, 14 ];

            my $status;
            if    ( $q1-1     > $max_q_uncov_n )     { $status = 'missing start' }
            elsif ( $qlen-$q2 > $max_q_uncov_c )     { $status = 'missing end' }
            elsif ( $nid  / $nmat < $min_ident )     { $status = 'low identity' }
            elsif ( $npos / $nmat < $min_pos )       { $status = 'low positives' }
            elsif ( ($q2-$q1+1)/$qlen < $min_q_cov ) { $status = 'low coverage' }
            elsif ( ($s2-$s1+1)/$slen < $min_s_cov ) { $status = 'long subject' }
            else
            {
                if ( $sseq )
                {
                    $sseq =~ s/-+//g;
                }
                else
                {
                    if ( ! keys %seqs )
                    {
                        if ( ref( $seqs ) eq 'ARRAY' )
                        {
                            %seqs = map { $_->[0] => $_ } @$seqs;
                        }
                        elsif ( -f $seqs )
                        {
                            %seqs = map { $_->[0] => $_ } gjoseqlib::read_fasta( $seqs );
                        }
                        else
                        {
                            print STDERR "extract_with_psiblast could not locate sequences.\n";
                            return wantarray ? ( [], {} ) : [];
                        }
                    }
                    $sseq = substr( $seqs{$sid}->[2] || '', $s1, $s2-$s1+1 );
                }
                $sdef .= " ($s1-$s2/$slen)" if ( ( $s1 > 1 ) || ( $s2 < $slen ) );
                push @trimmed, [ $sid, $sdef, $sseq ];
                $status = 'included';
            }

            my $frac_id  = sprintf("%.3f", $nid/$nmat);
            my $frac_pos = sprintf("%.3f", $npos/$nmat);

            $report{ $sid } = [ $sid, $scr, $exp, $slen, $status, $frac_id, $frac_pos, $q1-1, $qlen-$q2, $s1-1, $slen-$s2 ];
        }
    }

    wantarray ? ( \@trimmed, \%report ) : \@trimmed;
}


#-------------------------------------------------------------------------------
#  Allow fragmentary matches inside of the highest-scoring hsp (or extending
#  at most 10 amino acids beyond):
#
#     $hsp = one_real_hsp( \@hsps )
#
#-------------------------------------------------------------------------------

sub one_real_hsp
{
    my ( $hsps ) = @_;
    return undef if ! ( $hsps && ( ref( $hsps ) eq 'ARRAY' ) && @$hsps );
    return $hsps->[0] if  @$hsps == 1;

    my $hsp0 = $hsps->[0];
    my $q1_min = $hsp0->[ 9] - 10;
    my $q2_max = $hsp0->[10] + 10;
    foreach my $hsp ( @$hsps[ 1 .. (@$hsps-1) ] )
    {
        return undef if ( $hsp->[ 9] < $q1_min ) || ( $hsp->[10] > $q2_max );
    }

    $hsp0;
}


#-------------------------------------------------------------------------------
#  Assemble a pseudo HSP from discontinuous BLAST HSPs:
#
#      $hsp = pseudo_hsp( \@hsps, \%options )
#
#-------------------------------------------------------------------------------
sub pseudo_hsp
{
    my ( $hsps, $options ) = @_;
    return undef if ! ( $hsps && ( ref( $hsps ) eq 'ARRAY' ) && @$hsps );
    return $hsps->[0] if  @$hsps == 1;
    $options ||= {};
    my $max_gap = $options->{ max_gap } ||  100;                              # Maximum unmatched region
    my $max_off = $options->{ max_off } || $options->{ max_offset } || 1000;  # Maximum offset

    my @hsps = sort { s_mid( $a ) <=> s_mid( $b ) } @$hsps;
    my $i0  = 0;
    my $scr = 0;
    my $s;
    for ( my $i = 0; $i < @hsps; $i++ )
    {
        if ( ( $s = $hsps[$i]->[0] ) > $scr ) { $i0 = $i; $scr = $s }
    }

    my $hsp0 = [ @{$hsps[$i0]} ];

    for ( my $i = $i0 - 1; $i >= 0; $i-- )
    {
        my ( $q1, $q2, $s1, $s2 ) = @$hsp0[ 9, 10, 12, 13 ];
        my $hsp = $hsps[$i];
        next unless $hsp->[9] < $q1 && $hsp->[12] < $s1;
        my $q_gap = $q1 - $hsp->[10] - 1;
        my $s_gap = $s1 - $hsp->[13] - 1;
        last if ( $q_gap > $max_gap ) && ( $s_gap > $max_gap );
        last if ( abs( $q_gap - $s_gap ) > $max_off );

        #  It is not worth trying to maintain the subject sequence

        $hsp0->[14] = '';

        #  If there is overlap, prorate the scores

        my $factor = 1;
        my $gap = $q_gap < $s_gap ? $q_gap : $s_gap;
        if ( $q_gap < 0 || $s_gap < 0 )
        {
            if ( $q_gap < $s_gap )
            {
                my $len = $hsp->[10] - $hsp->[9] + 1;
                $factor = ( $len + $q_gap ) / $len;
            }
            else
            {
                my $len = $hsp->[13] - $hsp->[12] + 1;
                $factor = ( $len + $s_gap ) / $len;
            }
        }

        $hsp0->[ 0] += $factor * $hsp->[0];
        $hsp0->[ 2] += $factor * $hsp->[2];
        $hsp0->[ 3] += $factor * $hsp->[3];
        $hsp0->[ 4] += $factor * $hsp->[4];
        $hsp0->[ 9]  = $hsp->[ 9];
        $hsp0->[12]  = $hsp->[12];
    }

    for ( my $i = $i0 + 1; $i < @hsps; $i++ )
    {
        my ( $q1, $q2, $s1, $s2 ) = @$hsp0[ 9, 10, 12, 13 ];
        my $hsp = $hsps[$i];
        next unless $hsp->[10] > $q2 && $hsp->[13] > $s2;
        my $q_gap = $hsp->[ 9] - $q2 - 1;
        my $s_gap = $hsp->[12] - $s2 - 1;
        last if ( $q_gap > $max_gap ) && ( $s_gap > $max_gap );
        last if ( abs( $q_gap - $s_gap ) > $max_off );

        #  It is not worth trying to maintain the subject sequence

        $hsp0->[14] = '';

        #  If there is overlap, prorate the scores

        my $factor = 1;
        my $gap = $q_gap < $s_gap ? $q_gap : $s_gap;
        if ( $q_gap < 0 || $s_gap < 0 )
        {
            if ( $q_gap < $s_gap )
            {
                my $len = $hsp->[10] - $hsp->[9] + 1;
                $factor = ( $len + $q_gap ) / $len;
            }
            else
            {
                my $len = $hsp->[13] - $hsp->[12] + 1;
                $factor = ( $len + $s_gap ) / $len;
            }
        }

        my $bitscr   = $factor * $hsp->[0];
        $hsp0->[ 0] += $bitscr;
        $hsp0->[ 1] *= 0.5 ** $bitscr;
        $hsp0->[ 2] += $factor * $hsp->[2];
        $hsp0->[ 3] += $factor * $hsp->[3];
        $hsp0->[ 4] += $factor * $hsp->[4];
        $hsp0->[10]  = $hsp->[10];
        $hsp0->[13]  = $hsp->[13];
    }

    $hsp0->[0] = int( $hsp0->[0] );
    $hsp0->[2] = int( $hsp0->[2] );
    $hsp0->[3] = int( $hsp0->[3] );
    $hsp0->[4] = int( $hsp0->[4] );

    $hsp0;
}


sub s_mid { $_[0]->[12] + $_[0]->[13] }


#-------------------------------------------------------------------------------
#  Do a PSI-BLAST search:
#
#   $structured_blast = blastpgp(  $dbfile,  $profilefile, \%options )
#   $structured_blast = blastpgp( \@dbseq,   $profilefile, \%options )
#   $structured_blast = blastpgp(  $dbfile, \@profileseq,  \%options )
#   $structured_blast = blastpgp( \@dbseq,  \@profileseq,  \%options )
#
#  Required:
#
#     $db_file      or \@db_seq
#     $profile_file or \@profile_seq
#
#  Options:
#
#     e_value     =>  $max_e_value   # maximum E-value of matches (D = 0.01)
#     max_e_value =>  $max_e_value   # maximum E-value of matches (D = 0.01)
#     n_result    =>  $max_results   # maximum matches returned (D = 1000)
#     n_thread    =>  $n_thread      # number of blastpgp threads (D = 4)
#     stderr      =>  $file          # place to send blast stderr (D = /dev/null)
#     query       =>  $q_file_name   # most complete
#     query       => \@q_seq_entry   # most complete
#     query_used  => \@q_seq_entry   # output
#
#-------------------------------------------------------------------------------

sub blastpgp
{
    my ( $db, $profile, $opts ) = @_;
    $opts ||= {};
    my $tmp = SeedAware::location_of_tmp( $opts );

    my ( $dbfile, $rm_db );
    if ( defined $db && ref $db )
    {
        ref $db eq 'ARRAY'
            && @$db
            || print STDERR "blastpgp requires one or more database sequences.\n"
               && return undef;
        my $dbfh;
        ( $dbfh, $dbfile ) = SeedAware::open_tmp_file( "blastpgp_db", '', $tmp );
        gjoseqlib::write_fasta( $dbfh, $db );
        close( $dbfh );
        $rm_db = 1;
    }
    elsif ( defined $db && -f $db )
    {
        $dbfile = $db;
    }
    else
    {
        die "blastpgp requires database.";
    }
    verify_db( $dbfile, 'P' );  # protein

    my ( $proffile, $rm_profile );
    if ( defined $profile && ref $profile )
    {
        ref $profile eq 'ARRAY'
            && @$profile
            or print STDERR "blastpgp requires one or more profile sequences.\n"
               and return undef;
        my $proffh;
        ( $proffh, $proffile ) = SeedAware::open_tmp_file( "blastpgp_profile", '', $tmp );
        #  Uppercase is critical to the behavior of blastpgp
        &print_alignment_as_pseudoclustal( $profile,  { file => $proffh, upper => 1 } );
        close( $proffh );
        $rm_profile = 1;
    }
    elsif ( defined $profile && -f $profile )
    {
        $proffile = $profile;
    }
    else
    {
        print STDERR "blastpgp requires a profile."
            and return undef;
    }

    my ( $qfile, $rm_query );
    my $query = $opts->{ query };
    if ( defined $query && ref $query )
    {
        ref $query eq 'ARRAY' && @$query == 3
            or print STDERR "blastpgp invalid query sequence.\n"
               and return undef;

        my $qfh;
        ( $qfh, $qfile ) = SeedAware::open_tmp_file( "blastpgp_query", '', $tmp );
        gjoseqlib::write_fasta( $qfh, [$query] );
        close( $qfh );
        $rm_query = 1;
    }
    elsif ( defined $query && -f $query )
    {
        $qfile = $query;
        ( $query ) = gjoseqlib::read_fasta( $qfile );
        $query
            or print STDERR "blastpgp failed to get query from '$qfile'."
                and return undef;
    }
    elsif ( $profile )    #  Build it from profile
    {
        $query = &representative_for_profile( $profile )
            or print STDERR "blastpgp failed to get query from the profile."
                and return undef;
        my $qfh;
        ( $qfh, $qfile ) = SeedAware::open_tmp_file( "blastpgp_query", '', $tmp );
        gjoseqlib::write_fasta( $qfh, [$query] );
        close( $qfh );
        $rm_query = 1;
    }
    else
    {
        print STDERR "blastpgp requires a query."
            and return undef;
    }

    $opts->{ query_used } = $query;

    my $e_val = $opts->{ e_value }  || $opts->{ max_e_val } || $opts->{ max_e_value }              ||    0.01;
    my $n_cpu = $opts->{ n_thread } || $opts->{ nthread }   || $opts->{ n_cpu } || $opts->{ ncpu } ||    4;
    my $nkeep = $opts->{ n_result } || $opts->{ nresult }                                          || 1000;

    my $blastpgp = SeedAware::executable_for( 'blastpgp' )
        or print STDERR "Could not find executable for program 'blastpgp'.\n"
            and return undef;

    my @cmd = ( $blastpgp,
                '-j', 1,          #  function is profile alignment
                '-B', $proffile,  #  location of profile
                '-d', $dbfile,
                '-i', $qfile,
                '-e', $e_val,
                '-b', $nkeep,
                '-v', $nkeep,
                '-t', 1           #  issues warning if not set
              );
    push @cmd, ( '-a', $n_cpu ) if $n_cpu;

    my $opts2 = { stderr => ( $opts->{stderr} || '/dev/null' ) };
    my $blastfh = SeedAware::read_from_pipe_with_redirect( @cmd, $opts2 )
           or print STDERR "Failed to open: '" . join( ' ', @cmd ), "'.\n"
              and return undef;
    my $out = &gjoparseblast::structured_blast_output( $blastfh, 1 );  # selfmatches okay
    close $blastfh;

    if ( $rm_db )
    {
        my @files = grep { -f $_ } map { ( $_, "$_.psq", "$_.pin", "$_.phr" ) } $dbfile;
        unlink @files if @files;
    }
    unlink $proffile if $rm_profile;
    unlink $qfile    if $rm_query;

    return $out;
}


#-------------------------------------------------------------------------------
#  Do psiblast against tranlated genomic DNA
#
#   $structured_blast = blastpgpn(  $dbfile,  $profilefile, \%options )
#   $structured_blast = blastpgpn( \@dbseq,   $profilefile, \%options )
#   $structured_blast = blastpgpn(  $dbfile, \@profileseq,  \%options )
#   $structured_blast = blastpgpn( \@dbseq,  \@profileseq,  \%options )
#
#  Required:
#
#     $db_file      or \@db_seq
#     $profile_file or \@profile_seq
#
#  Options:
#
#     aa_db_file =>  $trans_file    # put translation db here
#     e_value    =>  $max_e_value   # D = 0.01
#     max_e_val  =>  $max_e_value   # D = 0.01
#     n_cpu      =>  $n_cpu         # synonym of n_thread
#     n_result   =>  $max_seq       # D = 1000
#     n_thread   =>  $n_cpu         # D = 4
#     query      =>  $q_file_name   # most complete
#     query      => \@q_seq_entry   # most complete
#     query_used => \@q_seq_entry   # output
#     stderr     =>  $file          # place to send blast stderr (D = /dev/null)
#     tmp        =>  $temp_dir      # location for temp files
#
#  depricated alternatives:
#
#     prot_file  =>  $trans_file    # put translation db here
#-------------------------------------------------------------------------------

sub blastpgpn
{
    my ( $ndb, $profile, $opts ) = @_;
    $opts ||= {};
    my $tmp = SeedAware::location_of_tmp( $opts );

    $opts->{ aa_db_file } ||= $opts->{ prot_file } if defined $opts->{ prot_file };
    my $dbfile = $opts->{ aa_db_file };
    my $rm_db  = ! ( $dbfile && -f $dbfile );
    if ( defined $dbfile && -f $dbfile && -s $dbfile )
    {
        #  The tranaslated sequence database exists
    }
    elsif ( defined $ndb )
    {
        if ( ref $ndb eq 'ARRAY' && @$ndb )
        {
            ref $ndb eq 'ARRAY'
                && @$ndb
                || print STDERR "Bad sequence reference passed to blastpgpn.\n"
                   && return undef;
            my $dbfh;
            if ( $dbfile )
            {
                open( $dbfh, '>', $dbfile );
            }
            else
            {
                ( $dbfh, $dbfile ) = SeedAware::open_tmp_file( "blastpgpn_db", '', $tmp );
            }
            $dbfh or print STDERR 'Could not open $dbfile.'
                and return undef;
            foreach ( @$ndb )
            {
                gjoseqlib::write_alignment_as_fasta( $dbfh, six_translations( $_ ) );
            }
            close( $dbfh );
        }
        elsif ( -f $ndb && -s $ndb )
        {
            my $dbfh;
            open( $dbfh, '>', $dbfile )
                or print STDERR "Could not open protein database file '$dbfile'.\n"
                    and return undef;
            my $entry;
            while ( $entry = gjoseqlib::next_fasta_entry( $ndb ) )
            {
                gjoseqlib::write_alignment_as_fasta( $dbfh, six_translations( $entry ) );
            }
            close( $dbfh );
        }
        else
        {
            print STDERR "blastpgpn requires a sequence database."
                and return undef;
        }
    }
    else
    {
        die "blastpgpn requires a sequence database.";
    }
    verify_db( $dbfile, 'P' );  # protein

    my ( $proffile, $rm_profile );
    if ( defined $profile && ref $profile )
    {
        ref $profile eq 'ARRAY'
            && @$profile
            || print STDERR "blastpgpn requires one or more profile sequences.\n"
               && return undef;
        my $proffh;
        ( $proffh, $proffile ) = SeedAware::open_tmp_file( "blastpgpn_profile", '', $tmp );
        &print_alignment_as_pseudoclustal( $proffh,  { file => $proffile, upper => 1 } );
        close( $proffh );
        $rm_profile = 1;
    }
    elsif ( defined $profile && -f $profile )
    {
        $proffile = $profile;
    }
    else
    {
        print STDERR "blastpgpn requires profile."
            and return undef;
    }

    my ( $qfile, $rm_query );
    my $query = $opts->{ query };
    if ( defined $query && ref $query )
    {
        ref $query eq 'ARRAY' && @$query == 3
            or print STDERR "blastpgpn invalid query sequence.\n"
               and return undef;

        my $qfh;
        ( $qfh, $qfile ) = SeedAware::open_tmp_file( "blastpgpn_query", '', $tmp );
        gjoseqlib::write_fasta( $qfh, [$query] );
        close( $qfh );
        $rm_query = 1;
    }
    elsif ( defined $query && -f $query )
    {
        $qfile = $query;
        ( $query ) = gjoseqlib::read_fasta( $qfile );
    }
    elsif ( $profile )    #  Build it from profile
    {
        $query = &representative_for_profile( $profile );
        my $qfh;
        ( $qfh, $qfile ) = SeedAware::open_tmp_file( "blastpgpn_query", '', $tmp );
        gjoseqlib::write_fasta( $qfh, [$query] );
        close( $qfh );
        $rm_query = 1;
    }
    else
    {
        print STDERR "blastpgpn requires a query."
            and return undef;
    }

    $opts->{ query_used } = $query;

    my $e_val = $opts->{ e_value }  || $opts->{ max_e_val } || $opts->{ max_e_value }              ||    0.01;
    my $n_cpu = $opts->{ n_thread } || $opts->{ nthread }   || $opts->{ n_cpu } || $opts->{ ncpu } ||    4;
    my $nkeep = $opts->{ n_result } || $opts->{ nresult }                                          || 1000;

    my $blastpgp = SeedAware::executable_for( 'blastpgp' )
        or print STDERR "Could not find executable for program 'blastpgp'.\n"
            and return undef;

    my @cmd = ( $blastpgp,
                '-j', 1,          #  function is profile alignment
                '-B', $proffile,  #  location of protein profile
                '-d', $dbfile,    #  protein database
                '-i', $qfile,     #  one protein from the profile
                '-e', $e_val,
                '-b', $nkeep,
                '-v', $nkeep,
                '-t', 1,          #  issues warning if not set
              );
    push @cmd, ( '-a', $n_cpu ) if $n_cpu;

    my $opts2 = { stderr => ( $opts->{stderr} || '/dev/null' ) };
    my $blastfh = SeedAware::read_from_pipe_with_redirect( @cmd, $opts2 )
           or print STDERR "Failed to open: '" . join( ' ', @cmd ), "'.\n"
              and return undef;
    my $out = &gjoparseblast::structured_blast_output( $blastfh );
    close $blastfh;

    if ( $rm_db )
    {
        my @files = grep { -f $_ } map { ( $_, "$_.psq", "$_.pin", "$_.phr" ) } $dbfile;
        unlink @files if @files;
    }
    unlink $proffile if $rm_profile;
    unlink $qfile    if $rm_query;

    #  Fix the blastp output to look like tblastn output

    foreach my $qdata ( @$out )
    {
        my %sdata;     #  There are now multiple sequences per subject DNA
        foreach my $sdata ( @{ $qdata->[3] } )
        {
            my ( $sid, $sdef, undef, $hsps ) = @$sdata;
            my $fr;
            ( $sid, $fr ) = $sid =~ m/^(.*)\.([-+]\d)$/;
            my ( $b, $e, $slen ) = $sdef =~ m/(\d+)-(\d+)\/(\d+)$/;
            $sdef =~ s/ ?\S+$//;
            my $sd2 = $sdata{ $sid } ||= [ $sid, $sdef, $slen, [] ];
            foreach ( @$hsps ) { adjust_hsp( $_, $fr, $b ); push @{$sd2->[3]}, $_ }
        }

        #  Order the hsps for each subject

        foreach my $sid ( keys %sdata )
        {
            my $hsps = $sdata{ $sid }->[3];
            @$hsps = sort { $b->[0] <=> $a->[0] } @$hsps;
        }

        #  Order the subjects for the query

        @{$qdata->[3]} = map  { $_->[0] }                    # remove score
                         sort { $b->[1] <=> $a->[1] }        # sort by score
                         map  { [ $_, $_->[3]->[0]->[0] ] }  # tag with top score
                         map  { $sdata{ $_ } }               # subject data
                         keys %sdata;                        # subject ids
    }

    return $out;
}


#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  When search is versus six frame translation, there is a need to adjust
#  the frame and location information in the hsp back to the DNA coordinates.
#
#     adjust_hsp( $hsp, $frame, $begin )
#
#   0   1    2    3    4   5    6    7   8  9 10   11  12 13  14
#  scr Eval nseg Eval naln nid npos ngap fr q1 q2 qseq s1 s2 sseq
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub adjust_hsp
{
    my ( $hsp, $fr, $b ) = @_;
    $hsp->[8] = $fr;
    if ( $fr > 0 )
    {
        $hsp->[12] = $b + 3 * ( $hsp->[12] - 1 );
        $hsp->[13] = $b + 3 * ( $hsp->[13] - 1 ) + 2;
    }
    else
    {
        $hsp->[12] = $b - 3 * ( $hsp->[12] - 1 );
        $hsp->[13] = $b - 3 * ( $hsp->[13] - 1 ) - 2;
    }
}


#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Do a six frame translation for use by blastpgpn.  This modifications of
#  the identifiers and definitions are essential to the interpretation of
#  the blast results.  The program 'translate_fasta_6' produces the same
#  output format, and is much faster.
#
#   @translations = six_translations( $nucleotide_entry )
#
#  The ids are modified by adding ".frame" (+1, +2, +3, -1, -2, -3).
#  The definition is mofidified by adding " begin-end/of_length".
#  NCBI frame numbers reverse strand translation frames from the end of the
#  sequence (i.e., the beginning of the complement of the strand).
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub six_translations
{
    my ( $id, $def, $seq ) = map { defined($_) ? $_ : '' } @{ $_[0] };
    my $l = length( $seq );

    return () if $l < 15;

    #                    fr   beg    end
    my @intervals = ( [ '+1',  1,   $l - (  $l    % 3 ) ],
                      [ '+2',  2,   $l - ( ($l-1) % 3 ) ],
                      [ '+3',  3,   $l - ( ($l-2) % 3 ) ],
                      [ '-1', $l,    1 + (  $l    % 3 ) ],
                      [ '-2', $l-1,  1 + ( ($l-1) % 3 ) ],
                      [ '-3', $l-2,  1 + ( ($l-2) % 3 ) ]
                    );
    my ( $fr, $b, $e );

    map { ( $fr, $b, $e ) = @$_;
          [ "$id.$fr", "$def $b-$e/$l", gjoseqlib::translate_seq( gjoseqlib::DNA_subseq( \$seq, $b, $e ) ) ]
        } @intervals;
}


#-------------------------------------------------------------------------------
#  Get an input file handle, and boolean on whether to close or not:
#
#  ( \*FH, $close ) = input_file_handle(  $filename );
#  ( \*FH, $close ) = input_file_handle( \*FH );
#  ( \*FH, $close ) = input_file_handle( );                   # D = STDIN
#
#-------------------------------------------------------------------------------

sub input_file_handle
{
    my ( $file, $umask ) = @_;

    my ( $fh, $close );
    if ( defined $file )
    {
        if ( ref $file eq 'GLOB' )
        {
            $fh = $file;
            $close = 0;
        }
        elsif ( -f $file )
        {
            open( $fh, "<$file") || die "input_file_handle could not open '$file'.\n";
            $close = 1;
        }
        else
        {
            die "input_file_handle could not find file '$file'.\n";
        }
    }
    else
    {
        $fh = \*STDIN;
        $close = 0;
    }

    return ( $fh, $close );
}


#-------------------------------------------------------------------------------
#  Get an output file handle, and boolean on whether to close or not:
#
#  ( \*FH, $close ) = output_file_handle(  $filename );
#  ( \*FH, $close ) = output_file_handle( \*FH );
#  ( \*FH, $close ) = output_file_handle( );                   # D = STDOUT
#
#-------------------------------------------------------------------------------

sub output_file_handle
{
    my ( $file, $umask ) = @_;

    my ( $fh, $close );
    if ( defined $file )
    {
        if ( ref $file eq 'GLOB' )
        {
            $fh = $file;
            $close = 0;
        }
        else
        {
            open( $fh, ">$file") || die "output_file_handle could not open '$file'.\n";
            chmod 0664, $file;  #  Seems to work on open file!
            $close = 1;
        }
    }
    else
    {
        $fh = \*STDOUT;
        $close = 0;
    }

    return ( $fh, $close );
}


#-------------------------------------------------------------------------------
#
#   print_blast_as_records(  $file, \@queries )
#   print_blast_as_records( \*FH,   \@queries )
#   print_blast_as_records(         \@queries )     # STDOUT
#
#   \@queries = read_blast_from_records(  $file )
#   \@queries = read_blast_from_records( \*FH )
#   \@queries = read_blast_from_records( )          # STDIN
#
#  Three output record types:
#
#   Query \t qid \t qdef \t dlen
#   >     \t sid \t sdef \t slen
#   HSP   \t ...
#
#-------------------------------------------------------------------------------
sub print_blast_as_records
{
    my $file = ( $_[0] && ! ( ref $_[0] eq 'ARRAY' ) ? shift : undef );
    my ( $fh, $close ) = output_file_handle( $file );

    my $queries = shift;
    $queries && ref $queries eq 'ARRAY'
        or print STDERR "Bad blast data supplied to print_blast_as_records.\n"
           and return;

    foreach my $qdata ( @$queries )
    {
        $qdata && ref $qdata eq 'ARRAY' && @$qdata == 4
            or print STDERR "Bad blast data supplied to print_blast_as_records.\n"
               and return;

        my $subjcts = pop @$qdata;
        $subjcts && ref $subjcts eq 'ARRAY'
            or print STDERR "Bad blast data supplied to print_blast_as_records.\n"
               and return;

        print $fh join( "\t", 'Query', @$qdata ), "\n";
        foreach my $sdata ( @$subjcts )
        {
            $sdata && ref $sdata eq 'ARRAY' && @$sdata == 4
                or print STDERR "Bad blast data supplied to print_blast_as_records.\n"
                   and return;

            my $hsps = pop @$sdata;
            $hsps && ref $hsps eq 'ARRAY' && @$hsps
                or print STDERR "Bad blast data supplied to print_blast_as_records.\n"
                   and return;

            print $fh join( "\t", '>', @$sdata ), "\n";

            foreach my $hsp ( @$hsps )
            {
                $hsp && ref $hsp eq 'ARRAY' && @$hsp > 4
                    or print STDERR "Bad blast data supplied to print_blast_as_records.\n"
                       and return;
                print $fh join( "\t", 'HSP', @$hsp ), "\n";
            }
        }
    }

    close $fh if $close;
}


sub read_blast_from_records
{
    my ( $file ) = @_;

    my ( $fh, $close ) = input_file_handle( $file );
    $fh or print STDERR "read_blast_from_records could not open input file.\n"
                and return wantarray ? () : [];

    my @queries = ();
    my @qdata;
    my @subjects = ();
    my @sdata;
    my @hsps = ();

    local $_;
    while ( defined( $_ = <$fh> ) )
    {
        chomp;
        my ( $type, @datum ) = split /\t/;
        if ( $type eq 'Query' )
        {
            push @subjects, [ @sdata, [ @hsps     ] ] if @hsps;
            push @queries,  [ @qdata, [ @subjects ] ] if @qdata;
            @qdata = @datum;
            @sdata = ();
            @subjects = ();
            @hsps = ();
        }
        elsif ( $type eq '>' )
        {
            push @subjects, [ @sdata, [ @hsps ] ] if @hsps;
            @sdata = @datum;
            @hsps = ();
        }
        elsif ( $type eq 'HSP' )
        {
            push @hsps, \@datum;
        }
    }

    close $fh if $close;

    push @subjects, [ @sdata, [ @hsps     ] ] if @hsps;
    push @queries,  [ @qdata, [ @subjects ] ] if @qdata;

    wantarray ? @queries : \@queries;
}


sub verify_db
{
    my ( $db, $type ) = @_;
    
    my @args;
    if ( $type =~ m/^p/i )
    {
        @args = ( "-p", "T", "-i", $db ) unless ((-s "$db.psq") && (-M "$db.psq" <= -M $db)) || ((-s "$db.00.psq") && (-M "$db.00.psq" <= -M $db));
    }
    else
    {
        @args = ( "-p", "F", "-i", $db ) unless ((-s "$db.nsq") && (-M "$db.nsq" <= -M $db)) || ((-s "$db.00.nsq") && (-M "$db.00.nsq" <= -M $db));
    }

    @args or return ( -s $db ? 1 : 0 );


    #
    #  Find formatdb appropriate for the excecution environemnt.
    #

    my $prog = SeedAware::executable_for( 'formatdb' );
    if ( ! $prog )
    {
        warn "gjoalignandtree::verify_db: formatdb program not found.\n";
        return 0;
    }

    my $rc = system( $prog, @args );

    if ( $rc != 0 )
    {
        my $cmd = join( ' ', $prog, @args );
        warn "gjoalignandtree::verify_db: formatdb failed with rc = $rc: $cmd\n";
        return 0;
    }

    return 1;
}


1;
