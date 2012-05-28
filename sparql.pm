package sparql;

use HTTP::Request::Common;
use LWP::UserAgent;
use LWP::ConnCache;
use URI::Escape;
use XML::Simple;
use strict;

sub new {
    my $class = shift;
    my $ua = LWP::UserAgent->new(keep_alive => 1);
    $ua->timeout(600);
    $ua->conn_cache(LWP::ConnCache->new());
    $ua->conn_cache->total_capacity(10);
    $ua->agent("sparql.pm/1.1");
    my $self = {
        "_ua" => $ua
    };
    bless $self, $class;

    return $self
}

sub query {
    my ($self, $uri, $tquery) = @_;

    if (!$uri) {
        warn "sparql_query() called without endpoint";
        return ();
    }

    my $query = uri_escape($tquery);
    my $ruri;
    if ($uri =~ /\?/) {
        $ruri = $uri.'&query='.$query;
    } else {
        $ruri = $uri.'?query='.$query;
    }

    my $ret;
    my $response = $self->{'_ua'}->get($ruri, 'Accept' => 'text/tab-separated-values, application/sparql-results+xml, application/x-turtle, text/rdf+n3');
    if ($response->is_success) {
        $ret = $response->decoded_content;
    } elsif ($response->header("Client-Aborted")) {
        warn "Response timeout";

        return ();
    } else {
        warn $response->status_line.": ".$tquery;

        return ();
    }

    my $tsv = ($response->header('Content-Type') =~ m/^text\/tab-separated-values/i);
    my $sr = ($response->header('Content-Type') =~ m/^application\/sparql-results\+xml/i);
    my @retrows = ();
    if ($tsv) {
        my @rows = split("\n", $ret);
        my $header = shift @rows;
        if (!$header) {
            warn("no header from query");
            return ();
        }
        $header =~ s/^\s+//;
        my @cols = grep(s/^[\?\$]//, split("\t", $header));
        while (my $row = shift @rows) {
            if ($row =~ /^#/) {
                warn("SPARQL warning: $row\n");
                next;
            }
            next if ($row =~ /^\s*$/);
            my @data = split("\t", $row);
            my %row = ();
            for my $h (@cols) {
                my $cell = shift @data;
                $row{$h} = $cell;
            }
            push(@retrows, \%row);
        }

        return \@retrows;
    } elsif ($sr) {
        my $tree = XMLin($ret, ForceArray => 1);
        #print Dumper($tree)."\n";
        my @retrows;

        my $rows = $tree->{'results'}->[0]->{'result'};
        for my $row (@{ $rows }) {
            my %row;
            for my $binding (keys %{$row->{'binding'}}) {
                #print($binding."\n");
                my $val = $row->{'binding'}->{$binding};
                if ($val->{'uri'}) {
                    $row{$binding} = '<'.$val->{'uri'}->[0].'>';
                } elsif ($val->{'literal'}) {
                    my $literal = $val->{'literal'}->[0];
                    my $content;

                    if (ref($literal)) {
                        $content = '"' . $val->{'literal'}->[0]->{'content'} . '"';
                        my $dt = $val->{'literal'}->[0]->{'datatype'};
                        my $lang = $val->{'literal'}->[0]->{'xml:lang'};

                        if ($dt) {
                            $content .= "^^<$dt>";
                        } elsif ($lang) {
                            $content .= '@' . $lang;
                        }
                    } else {
                        $content = '"' . $literal . '"';
                    }

                    $row{$binding} = $content;
                } elsif ($val->{'bnode'}) {
                    $row{$binding} = '_:'.$val->{'literal'}->[0];
                } else {
                    $row{$binding} = '???';
                }
            }
            push(@retrows, \%row);
        }
        
        return \@retrows;
    }

    return $ret;
}

sub update {
    my ($self, $uri, $tupdate) = @_;

    if (!$uri) {
        warn "SPARQL::update() called without endpoint";
        return ();
    }

    my $ret;
    my %form = ( 'update' => $tupdate );
    my $response = $self->{'_ua'}->post($uri, \%form);
    if ($response->is_success) {
        $ret = $response->decoded_content;
    } elsif ($response->header("Client-Aborted")) {
        warn "Response timeout";

        return undef;
    } else {
        warn $response->status_line.": ".$tupdate."\n".$response->decoded_content;

        return undef;
    }

    return $ret;
}

sub put {
	my ($self, $uri, $doc, $mime, $text) = @_;

	if (!$uri) {
		warn "SPARQL::update() called without endpoint";
		return undef;
	}

	if ($uri =~ /\?/) {
		$uri .= '&graph='.uri_escape($doc);
	} else {
		$uri .= '?graph='.uri_escape($doc);
	}
	my $response = $self->{'_ua'}->request(PUT $uri, 'Content-Type' => $mime, 'Content-Length' => length($text), 'Content' => $text);
	if ($response->is_success) {
		return $response->decoded_content;
	} elsif ($response->header("Client-Aborted")) {
		warn "Response timeout";

		return undef;
	}
	warn $response->status_line."\n".$response->decoded_content;

	return undef;
}

sub print {
    my ($self, $res) = @_;

    for my $row (@{$res}) {
        my $first = 1;
        for my $col (keys %{$row}) {
            if ($first) {
                $first = 0;
            } else {
                print(", ");
            }
            print('?'.$col.' = '.$row->{$col});
        }
        print("\n");
    }
}

sub chomp {
    my($self, $s) = @_;

    if (!$s) {
        return "";
    }

    if ($s =~ /^<(.*)>$/) {
        return $1;
    } elsif ($s =~ /"(.*)"/) {
        return $1;
    } elsif ($s =~ /"(.*)"^^<.*>$/) {
        return $1;
    }

    return $s;
}

1;

# vi:set expandtab sts=4 sw=4:
