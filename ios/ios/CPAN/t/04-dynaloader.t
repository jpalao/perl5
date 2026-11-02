use strict;
use warnings;
use Test::More;

use DynaLoader;

{
    package DynaLoaderTest::Exporter;
    require Exporter;
    our @ISA = qw(DynaLoader Exporter);
    our @EXPORT = qw(loader_test_export);
    sub loader_test_export { 'exported' }
}
{
    package DynaLoaderTest::Importer;
    DynaLoaderTest::Exporter->import;
}
my $export = DynaLoaderTest::Importer->can('loader_test_export');
is($export ? $export->() : undef, 'exported',
    'DynaLoader does not mask an inherited Exporter::import');

SKIP: {
    skip 'iOS runtime path is only initialized in the embedded runtime', 3
        unless $^O =~ /darwin-ios/;

    my $runtime_path = $DynaLoader::ios_runtime_path;
    ok(defined $runtime_path && -d $runtime_path,
        'iOS runtime path is initialized');

    my $reimported = eval q{use DynaLoader $DynaLoader::ios_runtime_path; 1};
    ok($reimported && defined $runtime_path
        && $DynaLoader::ios_runtime_path eq $runtime_path,
        'repeated DynaLoader use leaves the runtime path unchanged');

    eval { $DynaLoader::ios_runtime_path = 'changed' };
    like($@, qr/Modification of a read-only value attempted/,
        'iOS runtime path is read-only');
}

done_testing();
