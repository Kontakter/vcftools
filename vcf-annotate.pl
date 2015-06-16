#!/usr/bin/env perl
#
# Author: petr.danecek@sanger
#

use strict;
use warnings;
use Carp;
use Vcf;

my %filters =
(
    MinAB        => { dflt=>2, usage=>'INT', desc=>'Minimum number of alternate bases (INFO/DP4)', nick=>'a' },
    SnpCluster   => { dflt=>undef, usage=>'INT1,INT2', desc=>"Filters clusters of 'INT1' or more SNPs within a run of 'INT2' bases", nick=>'c' },
    MinDP        => { dflt=>2, usage=>'INT', desc=>"Minimum read depth (INFO/DP or INFO/DP4)", nick=>'d' },
    MaxDP        => { dflt=>10_000_000, usage=>'INT', desc=>"Maximum read depth (INFO/DP or INFO/DP4)", nick=>'D' },
    MinMQ        => { dflt=>10, usage=>'INT', desc=>"Minimum RMS mapping quality for SNPs (INFO/MQ)", nick=>'q' },
    SnpGap       => { dflt=>10, usage=>'INT', desc=>"SNP within INT bp around a gap to be filtered", nick=>'w' },
    GapWin       => { dflt=>3, usage=>'INT', desc=>"Window size for filtering adjacent gaps", nick=>'W' },
    StrandBias   => { dflt=>1e-4, usage=>'FLOAT', desc=>"Min P-value for strand bias (INFO/PV4)", nick=>'1' },
    BaseQualBias => { dflt=>0, usage=>'FLOAT', desc=>"Min P-value for baseQ bias (INFO/PV4)", nick=>'2' },
    MapQualBias  => { dflt=>0, usage=>'FLOAT', desc=>"Min P-value for mapQ bias (INFO/PV4)", nick=>'3' },
    EndDistBias  => { dflt=>1e-4, usage=>'FLOAT', desc=>"Min P-value for end distance bias (INFO/PV4)", nick=>'4' },
    RefN         => { dflt=>'', usage=>'', desc=>"Reference base is N", nick=>'r' },
    Qual         => { dflt=>'10', usage=>'INT', desc=>"Minimum value of the QUAL field", nick=>'Q' },
    VDB          => { dflt=>'0', usage=>'FLOAT', desc=>"Minimum Variant Distance Bias (INFO/VDB)", nick=>'v' },
    HWE          => { dflt=>undef, usage=>'FLOAT', desc=>"Minimum P-value for HWE and F<0 (invokes --fill-HWE)", nick=>'H' },
    HWE_G3       => { dflt=>undef, usage=>'FLOAT', desc=>"Minimum P-value for HWE and F<0 (INFO/HWE and INFO/G3)", nick=>'HG' },
    HWE2         => { dflt=>undef, usage=>'FLOAT', desc=>"Minimum P-value for HWE (plus F<0) (INFO/AC and INFO/AN or --fill-AC-AN)", nick=>'H2' },
);

my $opts = parse_params();
annotate($opts);

exit;

#--------------------------------

sub error
{
    my (@msg) = @_;
    if ( scalar @msg ) { confess @msg; }

    my @filters;
    for my $key (sort {lc($filters{$a}{nick}) cmp lc($filters{$b}{nick})} keys %filters)
    {
        push @filters, sprintf("\t%s, %-25s\t\t%s [%s]\n", $filters{$key}{nick},$key.'  '.$filters{$key}{usage},$filters{$key}{desc},defined($filters{$key}{dflt})? $filters{$key}{dflt} : '');
    }

    print
        "About: Annotates VCF file, adding filters or custom annotations. Requires tabix indexed file with annotations.\n",
        "   Currently it can annotate ID, QUAL, FILTER and INFO columns, but will be extended on popular demand.\n",
        "   For examples of user-defined filters see online documentation or examples/filters.txt in vcftools distribution.\n",
        "Usage: cat in.vcf | vcf-annotate [OPTIONS] > out.vcf\n",
        "Options:\n",
        "   -a, --annotations <file.gz>         The tabix indexed file with the annotations: CHR\\tFROM[\\tTO][\\tVALUE]+.\n",
        "   -c, --columns <list>                The list of columns in the annotation file, e.g. CHROM,FROM,TO,-,QUAL,INFO/STR,INFO/GN. The dash\n",
        "                                           in this example indicates that the third column should be ignored. If TO is not\n",
        "                                           present, it is assumed that TO equals to FROM. When REF and ALT columns are present, only\n",
        "                                           matching lines are annotated.\n",
        "   -d, --description <file|string>     Header annotation, e.g. key=INFO,ID=HM2,Number=0,Type=Flag,Description='HapMap2 membership'.\n",
        "                                           The descriptions can be read from a file, one annotation per line.\n",
        "       --fill-AC-AN                    (Re)Calculate AC and AN tags\n",
        "       --fill-HWE                      (Re)Calculate HWE, AC and AN tags\n",
        "       --fill-ICF                      (Re)Calculate Inbreeding Coefficient F, HWE, AC and AN\n",
        "       --fill-type                     Annotate INFO/TYPE with snp,del,ins,mnp,complex\n",
        "   -f, --filter <file|list>            Apply filters, list is in the format flt1=value/flt2/flt3=value/etc. If argument to -f is a file,\n",
        "                                           user-defined filters be applied. See User Defined Filters below.\n",
        "   -H, --hard-filter                   Remove lines with FILTER anything else than PASS or \".\"\n",
        "   -n, --normalize-alleles             Make REF and ALT alleles more compact if possible (e.g. TA,TAA -> T,TA).\n",
        "   -r, --remove <list>                 Comma-separated list of tags to be removed (e.g. ID,INFO/DP,FORMAT/DP,FILTER).\n",
        "   -h, -?, --help                      This help message.\n",
        "Filters:\n",
        sprintf("\t+  %-25s\t\tApply all filters with default values (can be overriden, see the example below).\n",''),
        sprintf("\t-X %-25s\t\tExclude the filter X\n",''),
        join('',@filters),
        "Examples:\n",
        "   zcat in.vcf.gz | vcf-annotate -a annotations.gz -d descriptions.txt -c FROM,TO,CHROM,ID,INFO/DP | bgzip -c >out.vcf.gz \n",
        "   zcat in.vcf.gz | vcf-annotate -f +/-a/c=3,10/q=3/d=5/-D -a annotations.gz -d key=INFO,ID=GN,Number=1,Type=String,Description='Gene Name' | bgzip -c >out.vcf.gz \n",
        "   zcat in.vcf.gz | vcf-annotate -a dbSNPv132.tab.gz -c CHROM,POS,REF,ALT,ID,-,-,- | bgzip -c >out.vcf.gz \n",
        "   zcat in.vcf.gz | vcf-annotate -r FILTER/MinDP | bgzip -c >out.vcf.gz \n",
        "Where descriptions.txt contains:\n",
        "   key=INFO,ID=GN,Number=1,Type=String,Description='Gene Name'\n",
        "   key=INFO,ID=STR,Number=1,Type=Integer,Description='Strand'\n",
        "The file dbSNPv132.tab.gz with dbSNP IDs can be downloaded from\n",
        "   ftp://ftp.sanger.ac.uk/pub/1000genomes/pd3/dbSNP/\n",
        "\n";
    exit -1;
}

sub parse_params
{
    $0 =~ s{^.+/}{}; $0 .= "($Vcf::VERSION)";
    my $opts = { args=>[$0, @ARGV], };
    while (defined(my $arg=shift(@ARGV)))
    {
        if ( $arg eq '-d' || $arg eq '--description' ) 
        { 
            my $desc = shift(@ARGV);
            if ( -e $desc )
            {
                open(my $fh,'<',$desc) or error("$desc: $!");
                while (my $line=<$fh>)
                {
                    if ( $line=~/^\s*$/ or $line=~/^#/ ) { next; }
                    chomp($line);
                    push @{$$opts{desc}}, $line;
                }
                close($fh);
            }
            else
            {
                push @{$$opts{desc}}, $desc; 
            }
            next;
        }
        if ( $arg eq '-f' || $arg eq '--filter' )
        {
            my $filter = shift(@ARGV);
            parse_filters($opts,$filter);
            next;
        }
        if ( $arg eq '-c' || $arg eq '--columns' ) 
        { 
            my $cols = shift(@ARGV);
            $$opts{cols} = [ split(/,/,$cols) ];
            next; 
        }
        if ( $arg eq '-r' || $arg eq '--remove' ) 
        { 
            my $tags = shift(@ARGV);
            my @tags = split(/,/,$tags);
            for my $tag (@tags)
            {
                my ($col,$tag) = split(m{/},$tag);
                if ( !defined $tag )
                {
                    if ( $col eq 'ID' ) { $$opts{remove}{$col}=1; next; }
                    if ( $col eq 'QUAL' ) { $$opts{remove}{$col}=1; next; }
                    if ( $col eq 'FILTER' ) { $$opts{remove}{$col}=1; next; }
                    $$opts{remove}{INFO}{$col}   = 1;
                    $$opts{remove}{FORMAT}{$col} = 1;
                }
                elsif ( $col eq 'FILTER' ) { $$opts{remove}{$col}{$tag} = 0; }
                else { $$opts{remove}{$col}{$tag} = 1; }
            }
            next;
        }
        if ( $arg eq '-n' || $arg eq '--normalize-alleles' ) { $$opts{normalize} = 1; next }
        if ( $arg eq '-a' || $arg eq '--annotations' ) { $$opts{annotations} = shift(@ARGV); next }
        if (                 $arg eq '--fill-type' ) { $$opts{fill_type}=1; $$opts{fill}=1; next }
        if (                 $arg eq '--fill-AC-AN' ) { $$opts{fill_ac_an} = 1; $$opts{fill}=1; next }
        if (                 $arg eq '--fill-HWE' ) { $$opts{fill_ac_an} = $$opts{fill_hwe} = 1; $$opts{fill}=1; next }
        if (                 $arg eq '--fill-ICF' ) { $$opts{fill_ac_an} = $$opts{fill_hwe} = $$opts{fill_icf} = 1; $$opts{fill}=1; next }
        if ( $arg eq '-t' || $arg eq '--tag' ) { $$opts{tag} = shift(@ARGV); next }
        if ( $arg eq '-H' || $arg eq '--hard-filter' ) { $$opts{hard_filter} = 1; next }
        if ( $arg eq '-?' || $arg eq '-h' || $arg eq '--help' ) { error(); }
        if ( -e $arg ) { $$opts{file}=$arg; next; }
        error("Unknown parameter \"$arg\". Run -h for help.\n");
    }
    if ( !exists($$opts{filters}) && !exists($$opts{udef_filters}) )
    {
        if ( !exists($$opts{annotations}) && !exists($$opts{remove}) && !exists($$opts{fill}) && !exists($$opts{normalize}) && !exists($$opts{hard_filter}) ) 
        { 
            error("Missing one of the -a, -f, -n, -r or --fill-* options.\n") 
        }
    }
    if ( exists($$opts{annotations}) && !exists($$opts{cols}) ) { error("Missing the -c option.\n"); }
    return $opts;
}

sub parse_user_defined_filters
{
    my ($opts,$str) = @_;
    my $filters = [ do $str ];
    if ( $@ ) { error("do $str: $@"); }
    for my $filter (@$filters)
    {
        if ( !exists($$filter{tag}) ) { error("Missing 'tag' key for one of the filters in $str\n"); }
        if ( $$filter{tag}=~m{^INFO/(.+)$} ) { $$filter{info_tag} = $1; }
        elsif ( $$filter{tag}=~m{^FORMAT/(.+)$} ) { $$filter{format_tag} = $1; }
        elsif ( $$filter{tag} eq 'Dummy' ) 
        { 
            $$filter{any_tag} = $1; 
            $$filter{name} = 'Dummy'; 
            $$filter{desc} = 'Dummy'; 
        }
        else { error("Currently only INFO, FORMAT and Dummy tags are supported. Could not parse the tag [$$filter{tag}]\n"); }

        my $name = $$filter{name};
        if ( !exists($$filter{name}) ) { error("Missing 'name' key for the filter [$$filter{tag}]\n"); }
        if ( !exists($$filter{desc}) ) { error("Missing 'desc' key for the filter [$$filter{tag}]\n"); }

        if ( exists($$filter{header}) )
        {
            push @{$$opts{desc}}, ref($$filter{header}) eq 'ARRAY' ? @{$$filter{header}} : $$filter{header};
        }
        elsif ( $$filter{tag} ne 'Dummy' )
        {
            push @{$$opts{desc}}, "key=FILTER,ID=$name,Description='$$filter{desc}'";
        }
        if ( !exists($$filter{apply_to}) or lc($$filter{apply_to}) eq 'all' ) 
        {
            $$opts{udef_filters}{'all'}{$name} = $filter;
            $$opts{udef_filters}{'s'}{$name}   = $filter;
            $$opts{udef_filters}{'i'}{$name}   = $filter;
        }
        elsif ( exists($$filter{apply_to}) and lc($$filter{apply_to}) eq 'snps' )
        {
            $$opts{udef_filters}{'s'}{$name}   = $filter;
            $$opts{udef_filters_typecheck_needed} = 1;
        }
        elsif ( exists($$filter{apply_to}) and lc($$filter{apply_to}) eq 'indels' )
        {
            $$opts{udef_filters}{'i'}{$name}   = $filter;
            $$opts{udef_filters_typecheck_needed} = 1;
        }
    }
}

sub parse_filters
{
    my ($opts,$str) = @_;

    if ( -e $str )
    {
        parse_user_defined_filters($opts,$str);
        return;
    }

    my $has_filters = 0;
    my $set_defaults = 0;
    my @filters = split(m{/},$str);
    for my $fltr (@filters)
    {
        if ( $fltr eq '+' ) { $set_defaults=1; last; }
    }

    my %mapping;
    for my $flt (keys %filters)
    {
        if ( exists($mapping{$filters{$flt}{nick}}) ) { error("FIXME: the nick $filters{$flt}{nick} is not unique.\n"); }
        $mapping{$filters{$flt}{nick}} = $flt;

        if ( !defined($filters{$flt}{dflt}) ) { next; }
        if ( $set_defaults )
        {
            $$opts{filters}{$flt} = $filters{$flt}{dflt};
        }
    }

    for my $filter (@filters)
    {
        my ($key,$val) = split(/=/,$filter);
        if ( $key eq '+' ) { next; }
        my $to_be_deleted = 0;
        if ( $key=~/^-(.+)$/ ) { $to_be_deleted=1; $key = $1; }
        if ( !exists($filters{$key}) ) { $key = $mapping{$key}; }
        if ( !exists($filters{$key}) && !exists($mapping{$key}) ) { error("The filter [$key] not recognised.\n"); }
        if ( $to_be_deleted ) { delete($$opts{filters}{$key}); next; }

        if ( $key eq 'c' || $key eq 'SnpCluster' ) 
        { 
            ($$opts{SnpCluster_count},$$opts{SnpCluster_win}) = split(/,/,$val);

            # Simple sanity check
            if ( $$opts{SnpCluster_count}>$$opts{SnpCluster_win} ) 
            { 
                error("Did you really mean snpCluster=$$opts{SnpCluster_count},$$opts{SnpCluster_win}? The win (INT2) must be bigger or equal to count (INT1)."); 
            }
            $$opts{SnpCluster_buffer} = [];
            push @{$$opts{desc}}, "key=FILTER,ID=SnpCluster,Description='$filters{SnpCluster}{desc} [win=$$opts{SnpCluster_win},count=$$opts{SnpCluster_count}]'";
            $has_filters = 1;
            next;
        }

        $$opts{filters}{$key} = $val;
        $has_filters = 1;
    }
    for my $key (keys %{$$opts{filters}})
    {
        push @{$$opts{desc}}, "key=FILTER,ID=$key,Description='$filters{$key}{desc}" . (defined $$opts{filters}{$key} ? " [$$opts{filters}{$key}]'" : "'");
    }
    if ( !$has_filters && !scalar keys %{$$opts{filters}} ) { delete($$opts{filters}); }
    if ( exists($$opts{filters}{HWE}) ) { $$opts{fill_ac_an}=$$opts{fill_hwe}=1; } 
}


# Convert text descriptions given on command line to hashes which will be 
#   passed to Vcf::add_header_line
sub parse_descriptions
{
    my ($descs) = @_;
    my @out;
    for my $str (@$descs)
    {
        my $desc = {};
        my $tmp = $str;
        while ($tmp)
        {
            my ($key,$value);
            if ( $tmp=~/^([^=]+)=["']([^\"]+)["']/ ) { $key=$1; $value=$2; }
            elsif ( $tmp=~/^([^=]+)=([^,"]+)/ && $1 eq 'Description' ) 
            {
                # The command line eats the quotes
                $key=$1; $value=$2.$';
                $$desc{$key} = $value;
                last;
            }
            elsif ( $tmp=~/^([^=]+)=([^,"]+)/ ) 
            { 
                $key=$1; $value=$2; 
            }
            else { error(qq[Could not parse the description: [$str]\n]); }
            $$desc{$key} = $value;

            $tmp = $';
            if ( $tmp=~/^,/ ) { $tmp = $'; }

        }
        if ( !exists($$desc{ID}) ) { error("No ID in description? [$str]\n"); }
        push @out, $desc;
    }
    return \@out;
}

# Create mapping from the annotation IDs to column indexes. The mapping is used
#   to determine which columns should be used from the annotation file. The
#   following structure is returned:
#       { 
#           CHROM => col_idx,
#           FROM  => col_idx,
#           TO    => col_idx,
#           annots => 
#           [
#               { col=>col_idx, id=>annot_id, vcf_col=>vcf_column, is_flag=>0 },
#           ]
#       }
#   If {annots}{is_flag} is nonzero, "annot_id" will be written to VCF instead of "annot_id=value".
#   Currently only one VCF column (INFO) is supported. 
#
sub parse_columns
{
    my ($cols,$descriptions) = @_;

    my %desc = ();
    my %out  = ( annots=>[] );

    if ( !defined $cols ) { return \%out; }

    for my $d (@$descriptions)
    {
        $desc{$$d{key}.'/'.$$d{ID}} = $d;
    }

    for (my $i=0; $i<@$cols; $i++)
    {
        my $col = $$cols[$i];

        if ( $col eq '-' ) { next; }
        elsif ( $col eq 'CHROM' ) { $out{$col}=$i; }
        elsif ( $col eq 'FROM' ) { $out{$col}=$i; }
        elsif ( $col eq 'POS' ) { $out{'FROM'}=$i; }
        elsif ( $col eq 'TO' ) { $out{$col}=$i; }
        elsif ( $col eq 'ID' ) { $out{$col}=$i; }
        elsif ( $col eq 'FILTER' ) { $out{$col}=$i; }
        elsif ( $col eq 'REF' ) { $out{$col}=$i; }
        elsif ( $col eq 'ALT' ) { $out{$col}=$i; }
        elsif ( $col eq 'QUAL' ) { $out{$col}=$i; }
        else
        {
            if ( !exists($desc{$col}) && exists($desc{"INFO/$col"}) )
            {
               print STDERR qq[The description for "$col" does not exist, assuming "INFO/$col"\n];
               $col = "INFO/$col";
            }

            if ( !exists($desc{$col}))
            { 
                error("Missing the -d parameter for the column [$col]\n"); 
            }
            if ( !($col=~m{^(.+)/(.+)$}) ) { error("Could not parse the column [$col].\n"); }
            my $key = $1;
            my $id  = $2;
            my $rec = { col=>$i, id=>$id, vcf_col=>$key, is_flag=>($desc{$col}{Type} eq 'Flag' ? 1 : 0) };
            push @{$out{annots}}, $rec;
            if ( $key ne 'INFO' ) { error("TODO: other than INFO columns\n"); }
        }
    }
    if ( !exists($out{CHROM}) ) { $out{CHROM}=0; }
    if ( !exists($out{FROM}) ) { $out{FROM}=1; }
    if ( !exists($out{TO}) ) { $out{TO}=$out{FROM}; }
    if ( exists($out{REF}) && !exists($out{ALT}) or !exists($out{REF}) && exists($out{ALT}) ) { error("Expected both REF and ALT columns in the annotation file.\n"); }
    return \%out;
}

sub annotate
{
    my ($opts) = @_;

    # Init the variables
    my $descs = parse_descriptions($$opts{desc});
    my $cols  = parse_columns($$opts{cols},$descs);

    # Open VCF file and add all required header lines
    my %args = exists($$opts{file}) ? (file=>$$opts{file}) : (fh=>\*STDIN);
    my $vcf = $$opts{vcf} = Vcf->new(%args);
    $vcf->parse_header();
    if ( exists($$opts{remove}) )
    {
        for my $col (keys %{$$opts{remove}})
        {
            if ( ref($$opts{remove}{$col}) ne 'HASH' ) 
            {
                # remove all filters at once
                if ( $col eq 'FILTER' ) { $vcf->remove_header_line(key=>$col); }
                next;
            }
            for my $tag (keys %{$$opts{remove}{$col}}) { $vcf->remove_header_line(key=>$col, ID=>$tag); }
        }
    }
    for my $desc (@$descs)
    {
        $vcf->add_header_line($desc,silent=>1);
    }
    if ( $$opts{fill_type} ) { $vcf->add_header_line({key=>'INFO',ID=>'TYPE',Number=>'A',Type=>'String',Description=>'Variant type'}); }
    if ( $$opts{fill_ac_an} )
    {
        $vcf->add_header_line({key=>'INFO',ID=>'AC',Number=>'A',Type=>'Integer',Description=>'Allele count in genotypes'});
        $vcf->add_header_line({key=>'INFO',ID=>'AN',Number=>1,Type=>'Integer',Description=>'Total number of alleles in called genotypes'});
    }
    if ( $$opts{fill_hwe} )
    {
        $vcf->add_header_line({key=>'INFO',ID=>'HWE',Number=>1,Type=>'Float',Description=>'Hardy-Weinberg equilibrium test (PMID:15789306)'});
        $vcf->add_header_line({key=>'INFO',ID=>'ICF',Number=>1,Type=>'Float',Description=>'Inbreeding coefficient F'});
    }
    $vcf->add_header_line({key=>'source',value=>join(' ',@{$$opts{args}})},append=>'timestamp');
    print $vcf->format_header();

    my ($prev_chr,$prev_pos,$annot_from,$annot_to,$annot_line);
    my @annots  = @{$$cols{annots}};
    my $id_col  = exists($$cols{ID}) ? $$cols{ID} : undef;
    my $fltr_col = exists($$cols{FILTER}) ? $$cols{FILTER} : undef;
    my $from_col = $$cols{FROM};
    my $to_col   = $$cols{TO};
    my $ref_col  = exists($$cols{REF}) ? $$cols{REF} : undef;
    my $alt_col  = exists($$cols{ALT}) ? $$cols{ALT} : undef;
    my $qual_col = exists($$cols{QUAL}) ? $$cols{QUAL} : undef;

    # Initialize the annotation reader
    my $reader;
    if ( exists($$opts{annotations}) )
    {
        $reader = Reader->new(file=>$$opts{annotations});
        my $line = $vcf->next_line();
        if ( !defined $line ) 
        {
            # VCF file is empty
            undef $reader;
        }
        else
        {
            my @rec = split(/\t/,$line);
            $prev_chr = $rec[0];
            $prev_pos = $rec[1];
            $vcf->_unread_line($line);
            $reader->open(region=>"$prev_chr:$prev_pos");
        }
    }

    while (defined $reader)
    {
        # Read next annotation group, i.e. all records with the same position (or overlapping in case of intervals)
        my (@annot_lines,$annot_prev_from,$annot_prev_to);
        while ($reader)
        {
            my $annot_line = $reader->next_line();
            if ( !defined $annot_line ) { last; }
            my $annot_from = $$annot_line[$from_col];
            my $annot_to   = $$annot_line[$to_col];
            if ( !@annot_lines )
            {
                push @annot_lines, $annot_line;
                $annot_prev_from = $annot_from;
                $annot_prev_to   = $annot_to;
                next;
            }
            if ( $annot_from <= $annot_prev_to or $annot_to <= $annot_prev_to )
            {
                push @annot_lines, $annot_line;
                if ( $annot_prev_to < $annot_to ) { $annot_prev_to = $annot_to; }
                next;
            }
            $reader->unread_line($annot_line);
            last;
        }

        # Now loop through the VCF records
        my $line;
        while ($line = $vcf->next_line())
        {
            my @rec = split(/\t/,$line);
            if ( $$opts{normalize} ) 
            { 
                my ($ref,@alts) = $vcf->normalize_alleles($rec[3],$rec[4]);  
                $rec[3] = $ref;
                $rec[4] = join(',',@alts);
            }
            my $chr = $rec[0];
            my $pos = $rec[1];
            chomp($rec[-1]);

            if ( $chr ne $prev_chr )
            {
                $vcf->_unread_line($line);
                $prev_chr = $chr;
                $prev_pos = $pos;
                $reader->open(region=>"$prev_chr:$prev_pos");
                last;
            }

            if ( exists($$opts{remove}) ) { remove_tags($opts,\@rec); }

            # Quick position-based check: Is there an annotation for this record?
            if ( !defined $annot_prev_from or $pos < $annot_prev_from )
            {
                output_line($opts,\@rec);
                next;
            }
            if ( $pos > $annot_prev_to )
            {
                $vcf->_unread_line($line);
                last;
            }
            
            # Initialize the REF,ALT-based check. If there are multiple records with the same
            #   position, they can appear in any order. A single ALT allele is expected in the 
            #   annot file but multiple ALTs can be present in the VCF. As long as one of them
            #   matches the annot file, the record will be annotated.
            # The annot file can contain mutliallelic sites too. At least one ALT from the VCF
            #   has to match an ALT from the annot file.
            my (%ref_alt_pairs);
            if ( defined $alt_col )
            {
                my $ref = $rec[3];
                for my $alt (split(/,/,$rec[4]))
                {
                    my ($r,@a) = $vcf->normalize_alleles($ref,$alt);
                    $ref_alt_pairs{$r.'-'.$a[0]} = 1;
                }
            }

            # Now fill the annotations; Existing annotations with the same tag will be overwritten 
            my %values = ();
            my %ids = ();
            for my $annot_line (@annot_lines)
            {
                # Skip annotation lines which are not relevant to this VCF record
                if ( $$annot_line[$from_col] > $pos or $$annot_line[$to_col] < $pos ) { next; }
                if ( defined $alt_col && $$annot_line[$ref_col] ne '.' )
                {
                    my $alt_match = 0;
                    for my $alt (split(/,/,$$annot_line[$alt_col]))
                    {
                        my ($r,@a) =  $vcf->normalize_alleles($$annot_line[$ref_col],$alt);
                        if ( exists($ref_alt_pairs{$r.'-'.$a[0]}) ) { $alt_match = 1; last; }
                    }
                    if ( !$alt_match ) { next; }
                }
                for my $info (@annots)
                {
                    my $val = $$annot_line[$$info{col}];

                    if ( $val eq '' or $val eq '.' ) { $val=undef; }       # Existing annotation should be removed
                    elsif ( $$info{is_flag} )
                    {
                        if ( $val ) { $val=''; }            # Flag annotation should be added
                        else { $val=undef; }                # Flag annotation should be removed
                    }

                    # A single undef value can be overriden by other overlapping records (?)
                    if ( !defined $val && exists($values{$$info{id}}) ) { next; }
                    elsif ( exists($values{$$info{id}}) && !defined $values{$$info{id}}[0] )
                    {
                        $values{$$info{id}}[0] = $val;
                        next;
                    }
                    push @{$values{$$info{id}}}, $val;
                }
                if ( defined $id_col && $$annot_line[$id_col] ne '' ) { $ids{$$annot_line[$id_col]} = 1; }
                if ( defined $fltr_col && $$annot_line[$fltr_col] ne '' ) { $rec[6] = $$annot_line[$fltr_col]; }
                if ( defined $qual_col && $$annot_line[$qual_col] ne '' ) { $rec[5] = $$annot_line[$qual_col]; }
            }
            if ( scalar keys %ids ) { $rec[2] = join(';', keys %ids); }
            if ( scalar keys %values )
            {
                for my $key (keys %values)
                {
                    # Cannot use join on undef values
                    $values{$key} = scalar @{$values{$key}} == 1 ? $values{$key}[0] : join(',', @{$values{$key}});
                }
                $rec[7] = $vcf->add_info_field($rec[7],%values);
            }
            output_line($opts,\@rec);
        }
        if ( !defined $line ) { last; }
    }

    # Finish the VCF, no annotations for this part
    while (my $line=$vcf->next_line)
    {
        my @rec = split(/\t/,$line);
        if ( $$opts{normalize} ) 
        {
            my ($ref,@alts) = $vcf->normalize_alleles($rec[3],$rec[4]);  
            $rec[3] = $ref;
            $rec[4] = join(',',@alts);
        }
        chomp($rec[-1]);
        if ( exists($$opts{remove}) ) { remove_tags($opts,\@rec); }
        output_line($opts,\@rec);
    }

    # Output any lines left in the buffer
    output_line($opts);
}


sub fill_ac_an_hwe
{
    my ($opts,$line) = @_;
    my $igt = $$opts{vcf}->get_tag_index($$line[8],'GT',':');
    if ( $igt==-1 ) { return; }
    my %counts     = ( 0=>0 );
    my %dpl_counts = ( 0=>0 );
    if ( $$line[4] ne '.' )
    {
        my $idx=0;
        my $cnt=0;
        $counts{++$cnt} = 0;
        while ( ($idx=index($$line[4],',',$idx))>0 ) { $idx++; $counts{++$cnt} = 0; }

    }
    my $nhets  = 0;
    my $ngts   = 0;
    my $ncols  = @$line;
    for (my $isample=9; $isample<$ncols; $isample++)
    {
        my $gt = $$opts{vcf}->get_field($$line[$isample],$igt);
        my ($a1,$a2) = $$opts{vcf}->split_gt($gt);
        if ( $a1 ne '.' ) { $counts{$a1}++ }
        if ( defined $a2 && $a2 ne '.' ) 
        { 
            $counts{$a2}++;
            if ( $a1 ne '.' )
            {
                $dpl_counts{$a1}++;
                $dpl_counts{$a2}++;
                if ( $a1 ne $a2 ) { $nhets++ }
                $ngts++;
            }
        }
    }

    my $an = 0;
    my $ac;
    my $max_ac = 0;
    for my $key (sort {$a<=>$b} keys %counts)
    {
        if ( $key eq 0 ) { $an += $counts{$key}; next; }
        if ( defined $ac ) { $ac .= ','; }
        $ac .= $counts{$key};
        $an += $counts{$key};
        if ( exists($dpl_counts{$key}) && $dpl_counts{$key}>$max_ac ) { $max_ac = $dpl_counts{$key}; }
    }

    my %tags = (AN=>$an);
    if ( defined $ac ) { $tags{AC}=$ac }
    my $nall = $dpl_counts{0} + $max_ac;
    if ( scalar keys %counts==2 )
    {
        if ( $$opts{fill_hwe} && $nall && scalar keys %counts==2 )
        {
            my $freq_obs = 2*$nhets/$nall;
            my $freq_exp = 2*($max_ac/$nall)*(1-($max_ac/$nall));
            $$opts{icf} = $freq_exp ? 1-$freq_obs/$freq_exp : 0;
            $$opts{hwe} = eval_hwe(($max_ac-$nhets)/2,($dpl_counts{0}-$nhets)/2,$nhets ,$line);
            $tags{HWE} = sprintf "%.6f", $$opts{hwe};
            if ( $$opts{fill_icf} )
            {
                $tags{ICF} = sprintf "%.5f", $$opts{icf};
            }
        }
    }
    $$line[7] = $$opts{vcf}->add_info_field($$line[7],%tags);
}

# Wigginton 2005, PMID: 15789306
sub eval_hwe
{
    my ($obs_hom1,$obs_hom2,$obs_hets , $line) = @_;
    if ( $obs_hom1 + $obs_hom2 + $obs_hets == 0 ) { return 1; }

    my $obs_homc = $obs_hom1 < $obs_hom2 ? $obs_hom2 : $obs_hom1;
    my $obs_homr = $obs_hom1 < $obs_hom2 ? $obs_hom1 : $obs_hom2;

    my $rare_copies = 2 * $obs_homr + $obs_hets;
    my $genotypes   = $obs_hets + $obs_homc + $obs_homr;

    my @het_probs = ((0) x ($rare_copies+1));

    # start at midpoint
    my $mid = int($rare_copies * (2 * $genotypes - $rare_copies) / (2 * $genotypes));
    # check to ensure that midpoint and rare alleles have same parity
    if (($rare_copies & 1) ^ ($mid & 1)) { $mid++; }

    my $curr_hets = $mid;
    my $curr_homr = ($rare_copies - $mid) / 2;
    my $curr_homc = $genotypes - $curr_hets - $curr_homr;

    $het_probs[$mid] = 1.0;
    my $sum = $het_probs[$mid];
    for ($curr_hets=$mid; $curr_hets > 1; $curr_hets -= 2)
    {
        $het_probs[$curr_hets - 2] = $het_probs[$curr_hets] * $curr_hets * ($curr_hets - 1.0) / (4.0 * ($curr_homr + 1.0) * ($curr_homc + 1.0));
        $sum += $het_probs[$curr_hets - 2];

        # 2 fewer heterozygotes for next iteration -> add one rare, one common homozygote
        $curr_homr++;
        $curr_homc++;
    }
    $curr_hets = $mid;
    $curr_homr = int(($rare_copies - $mid) / 2);
    $curr_homc = $genotypes - $curr_hets - $curr_homr;
    for ($curr_hets = $mid; $curr_hets <= $rare_copies - 2; $curr_hets += 2)
    {
        $het_probs[$curr_hets + 2] = $het_probs[$curr_hets] * 4.0 * $curr_homr * $curr_homc /(($curr_hets + 2.0) * ($curr_hets + 1.0));
        $sum += $het_probs[$curr_hets + 2];

        # add 2 heterozygotes for next iteration -> subtract one rare, one common homozygote
        $curr_homr--;
        $curr_homc--;
    }

    for (my $i = 0; $i <= $rare_copies; $i++)
    {
        $het_probs[$i] /= $sum;
    }

    my $p_hwe = 0.0;
    #  p-value calculation for p_hwe
    for (my $i = 0; $i <= $rare_copies; $i++)
    {
        if ($het_probs[$i] > $het_probs[$obs_hets]) { next; }
        $p_hwe += $het_probs[$i];
    }

    return $p_hwe > 1.0 ? 1.0 : $p_hwe;
}

sub fill_type
{
    my ($opts,$line) = @_;
    my @types;
    for my $alt (split(/,/,$$line[4]))
    {
        my ($type,$len,$ht) = $$opts{vcf}->event_type($$line[3],$alt);
        if ( $type eq 'i' ) { push @types, $len>0 ? 'ins' : 'del'; }
        elsif ( $type eq 's' ) { push @types, $len==1 ? 'snp' : 'mnp'; } 
        elsif ( $type eq 'o' ) { push @types, 'complex'; } 
        elsif ( $type eq 'b' ) { push @types, 'break'; } 
        elsif ( $type eq 'u' ) { push @types, 'other'; } 
    }
    $$line[7] = $$opts{vcf}->add_info_field($$line[7],TYPE=>(@types ? join(',',@types) : undef));
}


# Stage the lines and then apply filtering if requested, otherwise just print the line
sub output_line
{
    my ($opts,$line) = @_;

    if ( defined $line )
    {
        if ( $$opts{fill_ac_an} ) { fill_ac_an_hwe($opts,$line); }
        if ( $$opts{fill_type} ) { fill_type($opts,$line); }
    }

    if ( !exists($$opts{filters}) && !exists($$opts{udef_filters}) )
    {
        # No filters requested, print the line
        print_line($opts, $line);
        return;
    }

    if ( defined $line )
    {
        # Local filters return the line back immediately
        if ( scalar keys %{$$opts{filters}} )
        {
            $line = apply_local_filters($opts,$line);
        }
        if ( exists($$opts{udef_filters}) )
        {
            $line = apply_user_defined_filters($opts,$line);
        }
    }

    # Staging filters may return nothing or multiple lines. If $line is not defined, they will
    #   empty the buffers
    my @lines;
    if ( exists($$opts{filters}{SnpGap}) )
    {
        @lines = apply_snpgap_filter($opts,$line);
        if ( defined $line && !scalar @lines ) { return; }
    }
    elsif ( defined $line ) { @lines=($line); }

    if ( exists($$opts{filters}{GapWin}) )
    {
        my @tmp;
        if ( !defined $line ) { push @lines,undef; }
        for my $line (@lines)
        {
            push @tmp, apply_gapwin_filter($opts,$line);
        }
        @lines = @tmp;
    }
 
    if ( exists($$opts{SnpCluster_count}) )
    {
        my @tmp;
        if ( !defined $line ) { push @lines,undef; }
        for my $line (@lines)
        {
            push @tmp, apply_snpcluster_filter($opts,$line);
        }
        @lines = @tmp;
    }

    for my $line (@lines)
    {
        print_line($opts, $line);
    }
}

sub remove_tags
{
    my ($opts,$line) = @_;

    # Remove INFO tags
    for my $tag (keys %{$$opts{remove}{INFO}})
    {
        my $ifrom=0;
        my $ito;
        my $tag_len = length($tag);
        while (1)
        {
            $ifrom = index($$line[7],$tag,$ifrom);
            if ( $ifrom==-1 ) { last; }
            if ( $ifrom!=0 && substr($$line[7],$ifrom-1,1) ne ';' )
            { 
                $ifrom++;
                next; 
            }
            if ( length($$line[7])!=$ifrom+$tag_len )
            {
                my $c = substr($$line[7],$ifrom+$tag_len,1);
                if ( $c ne ';' && $c ne '=' ) { $ifrom+=$tag_len; next; }
            }
            $ito = index($$line[7],';',$ifrom+1);
            last;
        }
        if ( !defined $ito ) { next; }  # not found
        my $out;
        if ( $ifrom>0 )
        {
            $out .= substr($$line[7],0,$ifrom-1);
            if ( $ito!=-1 ) { $out .= ';'; }
        }
        if ( $ito!=-1 )
        {
            $out .= substr($$line[7],$ito+1);
        }
        $$line[7] = defined $out ? $out : '.';
    }

    # Remove FORMAT tags
    for my $tag (keys %{$$opts{remove}{FORMAT}})
    {
        my $idx = $$opts{vcf}->get_tag_index($$line[8],$tag,':');
        if ( $idx==-1 ) { next; }
        for (my $i=8; $i<@$line; $i++)
        {
            $$line[$i] = $$opts{vcf}->remove_field($$line[$i],$idx,':');
        }
    }

    # Remove FILTER
    if ( exists($$opts{remove}{FILTER}) )
    {
        $$line[6] = ref($$opts{remove}{FILTER}) eq 'HASH' ? $$opts{vcf}->add_filter($$line[6],%{$$opts{remove}{FILTER}}) : 'PASS';
    }

    # Remove ID and QUAL
    if ( exists($$opts{remove}{ID}) ) { $$line[2] = '.' }
    if ( exists($$opts{remove}{QUAL}) ) { $$line[5] = '.' }
}

sub apply_user_defined_filters
{
    my ($opts,$line) = @_;

    our($MATCH,$CHROM,$POS,$FAIL,$PASS,$RECORD,$VCF);
    $CHROM  = $$line[0];
    $POS    = $$line[1];
    $FAIL   = 1;
    $PASS   = 0;
    $RECORD = $line;
    $VCF    = $$opts{vcf};

    my %filters = ();
    if ( $$opts{udef_filters_typecheck_needed} )
    {
        # Check if the line has an indel, SNP or both
        for my $alt (split(/,/,$$line[4]))
        {
            my ($type,$len,$ht) = $$opts{vcf}->event_type($$line[3],$alt);
            if ( exists($$opts{udef_filters}{$type}) ) 
            {
                %filters = ( %filters, %{$$opts{udef_filters}{$type}} );
            }
        }
        # Return if the line does not have the wanted variant type
        if ( !scalar %filters ) { return $line; }
    }
    else
    {
        %filters = %{$$opts{udef_filters}{all}};
    }

    my %apply;
    for my $filter (values %filters)
    {
        if ( exists($$filter{info_tag}) )
        {
            $MATCH = $$opts{vcf}->get_info_field($$line[7],$$filter{info_tag});
            if ( !defined $MATCH ) { next; }
        }
        elsif ( exists($$filter{format_tag}) )
        {
            my $idx = $$opts{vcf}->get_tag_index($$line[8],$$filter{format_tag},':');
            if ( $idx<0 ) { next; }
            $MATCH = $$opts{vcf}->get_sample_field($line,$idx);
        }
        $apply{ $$filter{name} } = &{$$filter{test}} == $PASS ? 0 : 1;
    }
    if ( scalar keys %apply )
    {
        $$line[6] = $$opts{vcf}->add_filter($$line[6],%apply);
    }

    return $line;
}

sub apply_local_filters
{
    my ($opts,$line) = @_;

    if ( !defined $line ) { return; }

    my $filters = $$opts{filters};
    my %apply;

    if ( exists($$filters{RefN}) )
    {
        $apply{RefN} = ($$line[3]=~/N/) ? 1 : 0;
    }
    if ( exists($$filters{Qual}) && $$line[5] ne '.' )
    {
        $apply{Qual} = $$line[5] < $$filters{Qual} ? 1 : 0;
    }
    if ( exists($$filters{HWE_G3}) && $$line[7]=~/G3=([^,]+),([^,]+),/ )
    {
        my ($rr,$ra);
        $rr = $1; 
        $ra = $2; 
        $apply{HWE_G3} = 0;
        if ( $$line[7]=~/HWE_G3=([^;\t]+)/ && $1<$$filters{HWE_G3} ) 
        {
            my $p = 2*$rr + $ra;
            if ( $p>0 && $p<1 && (1-$ra)/($p*(1-$p))<0 )
            {
                $apply{HWE_G3} = 1;
            }
            #printf "xHWE: f=%f  rr=$rr ra=$ra hwe=$1 p=$p  ($$line[1])\n";
        }
    }
    if ( exists($$filters{HWE}) )
    {
        $apply{HWE} = $$opts{hwe}<$$filters{HWE} && $$opts{icf}<0 ? 1 : 0;
    }
    if ( exists($$filters{VDB}) && $$line[7]=~/VDB=([^;,\t]+)/ )
    {
        $apply{VDB} = $1 < $$filters{VDB} ? 1 : 0;
    }
    if ( exists($$filters{MinDP}) or exists($$filters{MaxDP}) )
    {
        my $dp;
        if ( $$line[7]=~/DP=(\d+)/ ) { $dp = $1; }
        elsif ( $$line[7]=~/DP4=(\d+),(\d+),(\d+),(\d+)/ ) { $dp = $1 + $2 + $3 + $4; }
        
        if ( defined $dp )
        {
            if ( exists($$filters{MinDP}) ) { $apply{MinDP} = $dp < $$filters{MinDP} ? 1 : 0; }
            if ( exists($$filters{MaxDP}) ) { $apply{MaxDP} = $dp > $$filters{MaxDP} ? 1 : 0; }
        }
    }
    if ( exists($$filters{MinAB}) && $$line[7]=~/DP4=\d+,\d+,(\d+),(\d+)/ )
    {
        $apply{MinAB} = $1 + $2 < $$filters{MinAB} ? 1 : 0;
    }
    if ( exists($$filters{MinMQ}) && $$line[7]=~/MQ=(\d+)/ )
    {
        $apply{MinMQ} = $1 < $$filters{MinMQ} ? 1 : 0;
    }
    if ( (exists($$filters{StrandBias}) or exists($$filters{BaseQualBias}) or exists($$filters{MapQualBias}) or exists($$filters{EndDistBias}))
            && $$line[7]=~/PV4=([^,]+),([^,]+),([^,]+),([^,;\t]+)/ )
    {
        if ( exists($$filters{StrandBias}) ) 
        { 
            $apply{StrandBias} = $1 < $$filters{StrandBias} ? 1 : 0;
        }
        if ( exists($$filters{BaseQualBias}) ) 
        { 
            $apply{BaseQualBias} = $2 < $$filters{BaseQualBias} ? 1 : 0;
        }
        if ( exists($$filters{MapQualBias}) ) 
        { 
            $apply{MapQualBias} = $3 < $$filters{MapQualBias} ? 1 : 0;
        }
        if ( exists($$filters{EndDistBias}) ) 
        { 
            $apply{EndDistBias} = $4 < $$filters{EndDistBias} ? 1 : 0;
        }
    }
    if ( scalar keys %apply )
    {
        $$line[6] = $$opts{vcf}->add_filter($$line[6],%apply);
    }
    return $line;
}

sub apply_snpgap_filter
{
    my ($opts,$line) = @_;
    if ( !exists($$opts{SnpGap_buffer}) ) { $$opts{SnpGap_buffer}=[]; }

    my $vcf = $$opts{vcf};
    my $win = $$opts{filters}{SnpGap};
    my $buffer = $$opts{SnpGap_buffer};
    my ($indel_chr,$indel_pos,$to);

    if ( defined $line )
    {
        # There may be multiple variants, look for an indel. Anything what is not ref can be filtered.
        my $is_indel = 0;
        my $can_be_filtered = 0;
        for my $alt (split(/,/,$$line[4]))
        {
            my ($type,$len,$ht) = $vcf->event_type($$line[3],$alt);
            if ( $type eq 'i' ) 
            { 
                $is_indel = 1; 
                $indel_chr = $$line[0];
                $indel_pos = $$line[1]+1;
            }
            elsif ( $type ne 'r' ) { $can_be_filtered = 1; }
        }
        # The indel boundaries are based on REF (POS+1,POS+rlen-1). This is not
        #   correct as the indel can begin anywhere in the VCF4.x record with
        #   respect to POS. Specifically mpileup likes to write REF=CAGAGAGAGA
        #   ALT=CAGAGAGAGAGA. Thus this filtering is more strict and may remove
        #   some valid SNPs.
        $to = $is_indel ? $$line[1]+length($$line[3])-1 : $$line[1];
        push @$buffer, { line=>$line, chr=>$$line[0], from=>defined $indel_pos ? $indel_pos : $$line[1], to=>$to, exclude=>0, can_be_filtered=>$can_be_filtered, is_indel=>$is_indel };
    }

    my $n = @$buffer;

    # Is the new line an indel? If yes, check the distance to all previous lines
    if ( defined $indel_chr )
    {
        for (my $i=0; $i<$n-1; $i++)
        {
            my $buf = $$buffer[$i];
            if ( $$buf{chr} ne $indel_chr ) { next; }
            if ( !$$buf{can_be_filtered} ) { next; }
            if ( $$buf{is_indel} ) { next; }
            if ( $$buf{to}>=$indel_pos-$win ) { $$buf{exclude}=1; }
        }
    }

    if ( defined $line && $$buffer[0]{chr} eq $$buffer[-1]{chr} && $win+$$buffer[0]{to}>=$$buffer[-1]{from} )
    {
        # There are not enough rows in the buffer: the SnpGap window spans them all. Wait until there is more rows
        #   or a new chromosome
        return ();
    }

    # 'Look-behind' filtering was done above, now comes 'look-ahead' filtering
    my $indel_to;
    for (my $i=0; $i<$n; $i++)
    {
        my $buf = $$buffer[$i];
        if ( $$buf{is_indel} )
        {
            $indel_to  = $$buf{to};
            $indel_chr = $$buf{chr};
            next;
        }
        if ( !defined $indel_to ) { next; }
        if ( !$$buf{can_be_filtered} ) { next; }
        if ( $$buf{chr} ne $indel_chr ) 
        {
            undef $indel_to;
            next;
        }
        if ( $$buf{from}<=$indel_to+$win ) { $$buf{exclude}=1; }
    }

    if (@$buffer)
    {
        # Output. If no $line was given, output everything
        $to = $$buffer[-1]{from}-$win;
        my $chr = $$buffer[-1]{chr};
        my @out;
        while (@$buffer)
        {
            if ( $$buffer[0]{chr} eq $chr && $$buffer[0]{to}+$win>=$to && defined $line ) { last; }

            my $buf = shift(@$buffer);
            if ( $$buf{exclude} )
            {
                $$buf{line}[6] = $$opts{vcf}->add_filter($$buf{line}[6],'SnpGap'=>1); 
            }
            else
            {
                $$buf{line}[6] = $$opts{vcf}->add_filter($$buf{line}[6],'SnpGap'=>0); 
            }
            push @out,$$buf{line};
        }
        return @out;
    }
    else
    {
        # NB(ignat): Output nothing if input vcf is empty
        my @out;
        return @out;
    }
}


sub apply_gapwin_filter
{
    my ($opts,$line) = @_;
    if ( !exists($$opts{GapWin_buffer}) ) { $$opts{GapWin_buffer}=[]; }

    my $vcf = $$opts{vcf};
    my $win = $$opts{filters}{GapWin};
    my $buffer = $$opts{GapWin_buffer};
    my $n = @$buffer;
    my ($indel_chr,$indel_pos,$to);

    if ( defined $line )
    {
        # There may be multiple variants, only indels can be filtered
        my $is_indel  = 0;
        my $indel_len = 0;
        for my $alt (split(/,/,$$line[4]))
        {
            my ($type,$len,$ht) = $vcf->event_type($$line[3],$alt);
            if ( $type eq 'i' ) 
            { 
                $is_indel = 1; 
                $indel_chr = $$line[0];
                $indel_pos = $$line[1] + 1;
                $indel_len = abs($len); # This may remove valid insertions but also artefacts
                last;
            }
        }
        $to = $$line[1] + $indel_len;
        my $af = 0;
        if ( $is_indel )
        {
            # Collect allele frequency to make an educated guess which of the indels to keep
            $af = $vcf->get_info_field($$line[7],'AF');
            if ( !defined $af ) 
            { 
                $af = $vcf->get_info_field($$line[7],'AF1'); 
                # assuming that all records have the same set of annotations, otherwise comparing later AC with AF will be wrong
                if ( !defined $af ) { $af = $vcf->get_info_field($$line[7],'AC'); }
            }
            if ( !defined $af ) { $af=0 }
            else { $af = $vcf->get_field($af,0,',') }
        }
        push @$buffer, { line=>$line, chr=>$$line[0], from=>defined $indel_pos ? $indel_pos : $$line[1], to=>$to, is_indel=>$is_indel, AF=>$af, exclude=>0 };
        # printf "%d-%d\t%d-%d\n", $$buffer[0]{from},$$buffer[0]{to},$$buffer[-1]{from},$$buffer[-1]{to};

        # Update the latest gap position and check if the buffer can be flushed
        if ( !exists($$opts{GapWin_chr}) )
        {
            $$opts{GapWin_chr} = $$line[0];
            $$opts{GapWin_to} = $$line[1];
        }
        my $flush = ( $$opts{GapWin_chr} eq $$line[0] && $$line[1]<=$$opts{GapWin_to} ) ? 0 : 1;

        if ( $is_indel ) 
        { 
            # Check distance to previous indels and set the exclude flags
            for (my $i=0; $i<$n; $i++)
            {
                if ( !$$buffer[$i]{is_indel} ) { next; }
                if ( $$buffer[$i]{to}>=$indel_pos-$win ) 
                { 
                    $$buffer[$i]{exclude}=1; 
                    $$buffer[-1]{exclude}=1; 
                }
            }
            if ( $$opts{GapWin_chr} ne $$line[0] or $to+$win>$$opts{GapWin_to} ) { $$opts{GapWin_to} = $to+$win; }
        }
        $$opts{GapWin_chr} = $$line[0];
        if ( !$flush ) { return (); }
        if ( !$is_indel ) { $$opts{GapWin_to} = 0; }
    }

    # Let one of the gaps go through. It may not be the best one, but as there are more
    #   it is likely that at least one of them is real. Better to have the wrong one 
    #   than miss it completely. Base the decision on AF. If not present, let the first 
    #   one through.
    my $max_af=-1;
    for (my $i=0; $i<$n; $i++)
    {
        if ( !$$buffer[$i]{exclude} ) { next; }
        if ( $max_af<$$buffer[$i]{AF} ) { $max_af=$$buffer[$i]{AF} }
    }
    for (my $i=0; $i<$n; $i++)
    {
        if ( !$$buffer[$i]{exclude} ) { next; }
        if ( $max_af==$$buffer[$i]{AF} ) { $$buffer[$i]{exclude}=0; last; }
    }
    my @out;
    for (my $i=0; $i<$n; $i++)
    {
        my $buf = shift(@$buffer);
        if ( $$buf{exclude} )
        {
            $$buf{line}[6] = $$opts{vcf}->add_filter($$buf{line}[6],'GapWin'=>1); 
        }
        else
        {
            $$buf{line}[6] = $$opts{vcf}->add_filter($$buf{line}[6],'GapWin'=>0); 
        }
        push @out,$$buf{line};
    }
    return @out;
}


sub apply_snpcluster_filter
{
    my ($opts,$line) = @_; 

    my $buffer = $$opts{SnpCluster_buffer};
    my $n = @$buffer;

    # The buffer is empty and the line contains only reference alleles, print directly
    if ( $n==0 && defined $line && $$line[4] eq '.' )
    {
        $$line[6] = $$opts{vcf}->add_filter($$line[6],'SnpCluster'=>0); 
        return $line;
    }

    # Store the line in buffer and check how many lines can be printed
    my $to;     # All lines up to and including this index will be printed
    my $win = $$opts{SnpCluster_win};
    if ( defined $line )
    {
        # Exclude REF (and maybe also other filters?) form SnpCluster
        my $can_be_filtered = $$line[4] eq '.' ? 0 : 1;
        push @$buffer, { line=>$line, chr=>$$line[0], pos=>$$line[1], can_be_filtered=>$can_be_filtered, in_cluster=>0 };
        $n++;

        # Does the buffer hold enough lines now?
        my $last_chr = $$buffer[-1]{chr};
        my $last_pos = $$buffer[-1]{pos};
        for (my $i=$n-1; $i>=0; $i--)
        {
            my $buf = $$buffer[$i];
            if ( $$buf{chr} ne $last_chr ) { $to=$i; last; }
            if ( $last_pos - $$buf{pos} >= $win ) { $to=$i; last; }
        }

        if ( !defined $to ) { return; }
    }
    if ( !defined $to ) { $to=$n-1; }

    # Calculate the number of variants within the window
    my $count = 0;
    my $max_count = $$opts{SnpCluster_count};
    my $start_chr = $$buffer[0]{chr};
    my $start_pos = $$buffer[0]{pos};
    my $idx;
    for ($idx=0; $idx<$n; $idx++)
    {
        my $buf = $$buffer[$idx];
        if ( $$buf{chr} ne $start_chr ) { last; }
        if ( $$buf{pos} - $win >= $start_pos ) { last; }
        if ( $$buf{can_be_filtered} ) { $count++; }
    }

    # If a SNP cluster was found, set the in_cluster flag for all relevant sites. 
    #   The buffer will be flushed and the orphans would pass unnoticed.
    if ( $count>=$max_count )
    {
        for (my $i=0; $i<$idx; $i++)
        {
            if ( $$buffer[$i]{can_be_filtered} ) { $$buffer[$i]{in_cluster}=1; }
        }
    }

    # Now output the lines, adding or removing the filter
    my @out = ();
    for (my $i=0; $i<=$to; $i++)
    {
        my $buf = shift(@$buffer);
        if ( $$buf{in_cluster} )
        {
            $$buf{line}[6] = $$opts{vcf}->add_filter($$buf{line}[6],'SnpCluster'=>1); 
        }
        else
        { 
            $$buf{line}[6] = $$opts{vcf}->add_filter($$buf{line}[6],'SnpCluster'=>0); 
        }
        push @out,$$buf{line};
    }

    # Output all non-variant lines at the beggining of the buffer
    while (@$buffer)
    {
        if ( $$buffer[0]{can_be_filtered} ) { last; }
        my $buf = shift(@$buffer);
        $$buf{line}[6] = $$opts{vcf}->add_filter($$buf{line}[6],'SnpCluster'=>0);
        push @out,$$buf{line};
    }
    return @out;
}

sub print_line
{
    my ($opts, $line) = @_;
    if ( !defined $line ) { return; }
    if ( $$opts{hard_filter} && $$line[6] ne '.' && $$line[6] ne 'PASS' ) { return; }
    print join("\t",@$line) . "\n";
}



#---------------------------------

package Reader;

use strict;
use warnings;
use Carp;

sub new
{
    my ($class,@args) = @_;
    my $self = @args ? {@args} : {};
    bless $self, ref($class) || $class;
    if ( !$$self{delim} ) { $$self{delim} = qr/\t/; }
    if ( !$$self{chr} ) { $$self{chr} = 0; }        # the index of the chromosome column (indexed from 0)
    if ( !$$self{from} ) { $$self{from} = 1; }      # the index of the from column 
    if ( !$$self{to} ) { $$self{to} = 2; }          # the index of the to column 
    return $self;
}

sub throw
{
    my ($self,@msg) = @_;
    confess @msg;
}

sub open
{
    my ($self,%args) = @_;
    if ( !$$self{file} ) { return; }
    $self->close();
    open($$self{fh},"tabix $$self{file} $args{region} |") or $self->throw("tabix $$self{file}: $!");
}

sub close
{
    my ($self) = @_;
    if ( !$$self{fh} ) { return; }
    close($$self{fh});
    delete($$self{fh});
    delete($$self{buffer});
}

sub unread_line
{
    my ($self,$line) = @_;
    unshift @{$$self{buffer}}, $line;
    return;
}

sub next_line
{
    my ($self) = @_;
    if ( !$$self{fh} ) { return undef; }    # Run in dummy mode
    if ( $$self{buffer} && @{$$self{buffer}} ) { return shift(@{$$self{buffer}}); }
    my $line;
    # Skip comments
    while (1)
    {
        $line = readline($$self{fh});
        if ( !defined $line ) { return undef; }
        if ( $line=~/^#/ ) { next; }
        last;
    }
    my @items = split($$self{delim},$line);
    chomp($items[-1]);
    return \@items;
}

