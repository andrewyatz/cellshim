#!/usr/bin/env perl
use Mojolicious::Lite;

helper stub_resp => sub {
  my $self = shift;
  return {
    apiVersion => 'v3',
    warning => q{},
    error => q{},
    queryOptions => $self->req()->params()->to_hash(),
    response => [],
  };
};

helper query_ensembl_rest => sub {
  my ($self, $url, $server) = @_;
  my $domain = {
    ensembl => 'rest.ensembl.org',
    grch37 => 'grch37.rest.ensembl.org',
    eg => 'rest.ensemblgenomes.org',
  }->{$server};
  $domain = 'rest.ensembl.org' if ! $domain;
  my $full_url = q{http://}.$domain.$url;
  return $self->query_rest($full_url);
};

helper query_rest => sub {
  my ($self, $url) = @_;
  my $ua = Mojo::UserAgent->new();
  my $res = $ua->get($url => {Accept => 'application/json', ContentType => 'application/json', 'Access-Control-Allow-Origin' => 'http://example.org'})->res();
  my $json = $res->json();
  my $time = $res->headers->header('X-Runtime');
  if (defined $time) {
    $time = int(($time*100));
  }
  else {
    $time = 0;
  }
  return ($json, $time);
};

helper map_bands => sub {
  my ($self, $ensembl_region) = @_;
  my $key = (exists $ensembl_region->{bands}) ? 'bands' : 'karyotype_band';
  my @cytobands = map { 
    { stain => '', name => $_->{id}, start => $_->{start}, end => $_->{end}} 
  } @{$ensembl_region->{$key}};
  return \@cytobands;
};

helper map_chromosome => sub {
  my ($self, $ensembl_region, $chromosome_name) = @_;
  $chromosome_name = $ensembl_region->{name} if exists $ensembl_region->{name};
  
  # Generate cytobands format from our bands
  my $cytobands = [];
  $cytobands = $self->map_bands($ensembl_region) if exists $ensembl_region->{karyotype_band} || $ensembl_region->{bands};
  
  my $chromosome = {
    cytobands => $cytobands, name => "${chromosome_name}", isCircular => $ensembl_region->{is_circular}, "size" => $ensembl_region->{length}, start => 1, end => $ensembl_region->{length}
  };
  return $chromosome;
};

get '/:species/genomic/chromosome/:chromosome/info' => sub {
  my $c = shift;
  my $resp = $c->stub_resp();
  my $species = $c->param('species');
  my $chromosome = $c->param('chromosome');
  my $url = "/info/assembly/${species}/${chromosome}?bands=1";
  
  my ($json, $time) = $c->query_ensembl_rest($url, 'grch37');
  
  $resp->{response} = [{
    id => "$chromosome", 
    "time" => 0, 
    dbTime => $time, 
    numResults => 1, 
    numTotalResults => 1, 
    warningMsg => q{}, 
    errorMsg => q{}, 
    resultType => q{},
    result => [{
      chromosomes => [$c->map_chromosome($json, $chromosome)],
    }],
  }];
  
  $c->render(json => $resp);
};

# Assumes a fall-through to Cellbase
get '/*' => sub {
  my $c = shift;
  
};

app->start;