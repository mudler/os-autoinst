package foobar;
use Mojo::Base -base;
has load => sub {0};    # This component can be just explictly loaded. Does not require autoload.
1;
