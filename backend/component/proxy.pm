package backend::component::proxy;

use Mojo::Base 'Mojolicious';
use Mojo::Server::Daemon;
use Mojo::Transaction::HTTP;
use bmwqemu;

has 'listening_address' => "127.0.0.1";
has 'listening_port'    => "9991";
has 'redirect_table'    => sub { {} };
has 'policy'            => "FORWARD";

sub startup {
    my $self = shift;
    $self->log->level("error");
    my $r = $self->routes;

    die "Invalid policy supplied for Proxy" unless ($self->policy eq "FORWARD" or $self->policy eq "DROP" or $self->policy eq "REDIRECT");
    bmwqemu::diag ">> Proxy server started at " . $self->listening_address . ":" . $self->listening_port;
    bmwqemu::diag ">> Proxy policy is " . $self->policy;
    bmwqemu::diag ">> Proxy redirect table: " if keys %{$self->redirect_table};
    foreach my $k (keys %{$self->redirect_table}) {
        bmwqemu::diag "\t $k => " . $self->redirect_table->{$k};
    }

    $r->any('*' => sub { $self->_handle_request(shift) });
    $r->any('/' => sub { $self->_handle_request(shift) });

}

sub _handle_request {
    my ($self, $controller) = @_;
    my $redirect_table = $self->redirect_table;
    $controller->render_later;

    my $requested_host = $controller->tx->req->url->base->host();
    bmwqemu::diag ">> Proxying Request for:" . $requested_host;

    $self->_redirect($controller);
}

sub _redirect {
    my $self       = shift;
    my $controller = shift;
    my $host_entry = $self->redirect_table;

    my $r_url     = $controller->tx->req->url;
    my $r_urlpath = $controller->tx->req->url->path;

    my $r_host         = $controller->tx->req->url->base->host();
    my $r_method       = $controller->tx->req->method();
    my $client_address = $controller->tx->remote_address;

    $controller->reply->not_found and return if $self->policy eq "DROP";

    bmwqemu::diag ">> Proxying Request for:" . $r_host;
    bmwqemu::diag ">> Proxy Request from:" . $client_address . " " . $r_method . " " . $r_host;

    #Start forging - FORWARD by default
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->req($controller->tx->req->clone());    #this is better, we keep also the same request

    if ($self->policy eq "REDIRECT" && exists $host_entry->{$r_host}) {
        $tx->req->url->parse("http://" . $host_entry->{$r_host});
    }
    elsif ($self->policy eq "FORWARD") {
        $tx->req->url->parse("http://" . $r_host);
    }

    $tx->req->url->path($r_urlpath);
    $tx->req->url->query($controller->tx->req->params);
    my $res = $self->ua->inactivity_timeout(20)->max_redirects(5)->connect_timeout(20)->request_timeout(10)->start($tx);

    bmwqemu::diag "!! Proxy error: Something went wrong when processing the request: " . join(" ", @{$tx->res->{'error'}}) if ($tx->res->error);

    $controller->tx->res($tx->res);
    $controller->rendered;
}

sub start {
    my $self = shift;
    Mojo::Server::Daemon->new(listen => ['http://' . $self->listening_address . ':' . $self->listening_port], app => $self)->run;
}

1;
