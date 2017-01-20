package MSAnnotator::Config;
use YAML 'LoadFile';
use Text::CSV;

# Load custom modukes
require Exporter;
use MSAnnotator::Base;

# Export functions
our @ISA = 'Exporter';
our @EXPORT = qw(load_config);

use constant CONFIG_FILENAME => "${ENV{'PWD'}}/config.yaml";

# Read configuration and export CONFIG hash
sub load_config {
  my $config = LoadFile(CONFIG_FILENAME);

  # Convert paths
  my $pwd = ${ENV{'PWD'}};
  my $assmblfn = (split('/', $config->{ncbi_assemblies_url}))[-1];
  $config->{taxon_file} = "$pwd/$config->{taxon_file}";
  $config->{data_dir} = "$pwd/$config->{data_dir}";
  $config->{known_assemblies} = "$pwd/$config->{known_assemblies}";
  $config->{ncbi_assemblies_file} = "$config->{data_dir}/$assmblfn";

  # Ensure data_dir exists
  if (! -e $config->{data_dir}) {
    mkdir $config->{data_dir} or croak "$!: $config->{data_dir}\n";
  }

  # Load annotate_file and add to config hash
  my $csv = Text::CSV->new({binary => 1, auto_diag => 1});
  open my $fh, "<", $config->{taxon_file} or croak "$!: $config->{taxon_file}\n";

  # Ensure header exists
  my @header = map { lc $_ } @{$csv->getline($fh)};
  croak "No taxon_id feild in annotate_file\n" if not 'taxon_id' ~~ @header;

  # Loop through and push ids to config
  $csv->column_names(@header);
  while (my $row = $csv->getline_hr($fh)) {
    push @{$config->{taxon_input}}, $row->{taxon_id};
  }
  return $config;
}

1;
