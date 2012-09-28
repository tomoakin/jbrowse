use strict;
use warnings;

use lib 'tests/perl_tests/lib';
use JBlibs;

use Test::More;

use File::Spec::Functions 'catfile';
use File::Temp;
use Capture::Tiny 'capture';

use FileSlurping 'slurp_tree';

my $tempdir = File::Temp->newdir;

## check behavior for missing ref seqs

my ( $stdout, $stderr ) = capture {
    system $^X, 'bin/prepare-refseqs.pl', (
        '--conf' => 'sample_data/raw/yeast_genbank.json',
        '--refs' => 'DOES NOT EXIST',
        '--out'  => $tempdir,
        );
};
ok( ! $?, 'script succeeded for nonexistent ref' );
like( $stderr, qr/DOES NOT EXIST.+not found/i, 'warning message looks right' );

## check basic formatting of volvox sequence

$tempdir = File::Temp->newdir;

system $^X, 'bin/prepare-refseqs.pl', (
    #'--refs'  => 'ctgA',
    '--fasta' => 'sample_data/raw/volvox/volvox.fa',
    '--out'   => $tempdir,
   );

my $output = slurp_tree( $tempdir );
is_deeply( $output,
           slurp_tree('tests/data/volvox_formatted_refseqs'),
           'got the right volvox formatted sequence',
          )
#    or diag explain $output
;

## check genbank formatting

$tempdir = File::Temp->newdir;

system $^X, 'bin/prepare-refseqs.pl', (
    '--refs'  => 'NC_001133',
    '--conf' => 'sample_data/raw/yeast_genbank.json',
    '--out'   => $tempdir,
   );

ok( !$?, 'yeast genbank formatting ran OK' );
my @chunks = glob("$tempdir/seq/NC_001133/*.txt");
is( scalar @chunks, 12, 'see 12 uncompressed seq chunks' ) or diag explain \@chunks;


## check compressed formatting
$tempdir = File::Temp->newdir;

system $^X, 'bin/prepare-refseqs.pl', (
    '--refs'  => 'NC_001133',
    '--conf' => 'sample_data/raw/yeast_genbank.json',
    '--out'   => $tempdir,
    '--compress',
   );

ok( !$?, 'yeast genbank formatting ran OK' );

@chunks = glob("$tempdir/seq/NC_001133/*.txtz");
is( scalar @chunks, 3, 'see 3 COMPRESSED seq chunks' );


## check formatting from gff

$tempdir = File::Temp->newdir;

system $^X, 'bin/prepare-refseqs.pl', (
    '--gff' => 'tests/data/embedded_sequence.gff3',
    '--out'   => $tempdir,
   );

$output = slurp_tree( $tempdir );

is_deeply( $output->{"seq/refSeqs.json"},
           [
               {
                   end => 10000,
                   length => 10000,
                   name => "Group1.36",
                   seqChunkSize => 20000,
                   seqDir => "seq/Group1.36",
                   start => 0,
               }
           ]);

## test formatting from a Bio::DB::SeqFeature::Store with a
## biodb-to-json.pl conf file

$tempdir = File::Temp->newdir();
diag $tempdir;
local $ENV{PATH} = "extlib/bin:$ENV{PATH}";

($stdout, $stderr) = capture {
   system 'bp_seqfeature_load.pl', (
        '--adaptor' => 'DBI::SQLite',
        '--dsn'     => "$tempdir/sqliteDB",
        '--create',
        'sample_data/raw/volvox/volvox.gff3',
        'sample_data/raw/volvox/volvox.fa',
       );
};
unlike( $stderr, qr/error/i, 'no errors stderr from bp_seqfeature_load' );
is( $stdout, '', 'nothing on stdout from bp_seqfeature_load' );

{ open my $conf, '>', "$tempdir/conf" or die; $conf->print( <<EOCONF ); }
{
   "TRACK DEFAULTS" : {
      "autocomplete" : "all",
      "class" : "feature"
   },
   "db_args" : {
      "-adaptor" : "DBI::SQLite",
      "-dsn" : "$tempdir/sqliteDB"
   },
   "description" : "Sequence Test Database",
   "db_adaptor" : "Bio::DB::SeqFeature::Store"
}
EOCONF



system $^X, 'bin/prepare-refseqs.pl', (
    '--conf' => "$tempdir/conf",
    '--out'   => "$tempdir/out",
    '--refs'  => 'ctgA,ctgB'
   );

$output = slurp_tree( "$tempdir/out" );
is_deeply( $output,
           slurp_tree('tests/data/volvox_formatted_refseqs'),
           'got the right volvox formatted sequence',
          );# or diag explain $output;

done_testing;

