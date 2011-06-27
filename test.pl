#!/usr/bin/perl

use sparql;
use strict;

my $sparql = sparql->new();

my $res = $sparql->query('http://dbpedia.org/sparql',
                         'SELECT * WHERE { ?s ?p ?o } LIMIT 10');

for my $row (@{$res}) {
	for my $col (keys %{$row}) {
		print('?'.$col.' = '.$row->{$col}."\n");
	}
	print("\n");
}
