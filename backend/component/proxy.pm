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

    die "Invalid policy supplied for Proxy" unless ($self->policy eq "FORWARD" or $self->policy eq "DROP" or $self->policy eq "REDIRECT" or $self->policy eq "SOFTREDIRECT");
    $self->_diag("Server started at " . $self->listening_address . ":" . $self->listening_port);
    $self->_diag("Default policy is " . $self->policy);
    $self->_diag("Redirect table: ") if keys %{$self->redirect_table};

    foreach my $k (keys %{$self->redirect_table}) {
        $self->_diag("\t $k => " . join(" ",@{$self->redirect_table->{$k}}));
    }

    $r->any('*' => sub { $self->_handle_request(shift) });
    $r->any('/' => sub { $self->_handle_request(shift) });

}

sub _handle_request {
    my ($self, $controller) = @_;
    $controller->render_later;
    $self->_redirect($controller);
}

sub _diag {
  my ($self,@messages) = @_;

  bmwqemu::diag ">> ".__PACKAGE__." @messages";

}

sub _redirect {
    my $self       = shift;
    my $controller = shift;
    my $host_entry = $self->redirect_table;

    my $r_url     = $controller->tx->req->url;
    my $r_urlpath = $controller->tx->req->url->path;

    my $r_host         = $controller->tx->req->url->base->host() || $controller->tx->req->content->headers->host();
    my $r_method       = $controller->tx->req->method();
    my $client_address = $controller->tx->remote_address;

    if (!$r_host) {
        $self->_diag("Request from:  could not be processed - cannot retrieve requested host");
        $controller->reply->not_found;
        return;
    }

    $self->_diag("Request from: " . $client_address . " method: " . $r_method . " to host:" . $r_host);
    $self->_diag("Requested url is: ".$controller->tx->req->url->to_string);
    if ($self->policy eq "DROP") {
        $self->_diag("Answering with 404");
        $controller->reply->not_found;
        return;
    }

    #Start forging - FORWARD by default
    my $tx = Mojo::Transaction::HTTP->new();
    $tx->req($controller->tx->req->clone());    #this is better, we keep also the same request
    $tx->req->url->path($r_urlpath);
    $tx->req->method($r_method);

    if($self->policy eq "SOFTREDIRECT") {
      my $redirect_to = @{$host_entry->{$r_host}}[0];
      my $redirect_replace = @{$host_entry->{$r_host}}[1];
      my $redirect_replace_with = @{$host_entry->{$r_host}}[2];
      $r_urlpath =~ s/$redirect_replace/$redirect_replace_with/g;
      my $url = Mojo::URL->new($redirect_to =~ /http:\/\// ? $redirect_to : "http://" . $redirect_to);

      if($url) {
        $tx->req->url->parse("http://" . $url->host);
        $tx->req->url->base->host($url->host);
        $tx->req->content->headers->host($url->host);
      }

      if ($url and $url->path ne "/") {
          $tx->req->url->path($url->path . $r_urlpath);
      }
    $self->_diag("Redirecting to: " . $tx->req->url->to_string);
    }
    elsif ($self->policy eq "REDIRECT" && exists $host_entry->{$r_host}) {
      my $redirect_to = @{$host_entry->{$r_host}}[0];
        my $url = Mojo::URL->new($redirect_to =~ /http:\/\// ? $redirect_to : "http://" . $redirect_to);
        if($url) {
          $tx->req->url->parse("http://" . $url->host);
          $tx->req->url->base->host($url->host);
          $tx->req->content->headers->host($url->host);
        }
        if ($url and $url->path ne "/") {
            $tx->req->url->path($url->path . $r_urlpath);
        }
        $self->_diag("Redirecting to: " . $tx->req->url->to_string);
    }
    elsif ($self->policy eq "FORWARD" or (($self->policy eq "REDIRECT" && !exists $host_entry->{$r_host})))
    {    # If policy is REDIRECT and no entry in the host table, fallback to FORWARD
        $tx->req->url->parse("http://" . $r_host);
        $self->_diag("No redirect rules for the host, forwarding to: " . $r_host);
    }

    $tx->req->url->query($controller->tx->req->params);
    my $req_tx = $self->ua->inactivity_timeout(20)->max_redirects(5)->connect_timeout(20)->request_timeout(10)->start($tx);

    unless($req_tx->result->is_success){
      $controller->reply->not_found;
      $self->_diag("!! error: Something went wrong when processing the request, return code from request is: " .$req_tx->result->code);
      return;
    }

    $controller->tx->res($req_tx->res);
    $controller->rendered;
}

sub start {
    my $self = shift;
    Mojo::Server::Daemon->new(listen => ['http://' . $self->listening_address . ':' . $self->listening_port], app => $self)->run;
}

1;
