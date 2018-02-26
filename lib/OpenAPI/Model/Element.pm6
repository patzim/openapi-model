use v6.c;
use JSON::Fast;

class X::OpenAPI::Model::TypeMismatch is Exception {
    has $.name;
    has $.field;
    has @.expected;
    has $.got;

    method message() {
        "Schema for $!name object expects {@!expected.map(*.^name).join(', ')} for field '$!field', but got {$!got.^name}"
    }
}

role OpenAPI::Model::Element [:%scalar, :%object, :$patterned = Nil, :$raw] {
    has $.model;
    has %.extensions;
    my %attr-lookup = ::?CLASS.^attributes(:local).map({ .name.substr(2) => $_ });

    method set-model($!model) {}

    method !handle-refy($spec, $v, $model) {
        if $spec<array> {
            return $v.map({
                    $_<$ref> ?? OpenAPI::Model::Reference.new($_<$ref>)
                             !! $spec<type>.deserialize($_, $model)
                }).Array;
        } elsif $spec<hash> {
            with $spec<raw> {
                return $spec<type>.new(|$v);
            }
            return $v.kv.map({
                    .key => .value<$ref> ?? OpenAPI::Model::Reference.new(.value<$ref>)
                                         !! $spec<type>.deserialize(.value, $model)
                }).Hash;
        } else {
            return $v<$ref> ?? OpenAPI::Model::Reference.new(ref => $v<$ref>)
                            !! $spec<type>.deserialize($v, $model);
        }
    }

    method !handle-object($spec, $v, $model) {
        with $spec<ref> {
            return self!handle-refy($spec, $v, $model);
        }
        if $spec<array> {
            return $v.map({$spec<type>.deserialize($_, $model)}).Array;
        } elsif $spec<hash> {
            return $v.map({ .key => $spec<type>.deserialize(.value, $model) }).Hash;
        } else {
            if $spec.defined {
                return $spec<type>.deserialize($v, $model);
            } elsif $patterned ~~ OpenAPI::Model::Element {
                return $patterned.deserialize($v, $model);
            } elsif $patterned {
                return $v;
            }
        }
    }

    method deserialize($source, $model) {
        my %attrs;
        for $source.kv -> $k, $v {
            if $k (elem) %scalar.keys {
                %attrs{$k} = $v;
            } else {
                %attrs{$k} = self!handle-object(%object{$k}, $v, $model);
            }
        }
        my $new = self.new(|%attrs);
        $new.set-model($model);
        $new;
    }
    method serialize() {
        my %structure;
        for %scalar.kv -> $k, $v {
            %structure{$k} = %attr-lookup{%scalar{$k}<attr> // $k}.get_value(self);
        }
        for %object.kv -> $k, $v {
            %structure{$k} = %attr-lookup{%object{$k}<attr> // $k}.get_value(self).serialize;
        }
        %structure;
    }

    submethod BUILD(*%args where {
                           my $keys = .keys (-) (%scalar.keys (|) %object.keys);
                           $keys .= grep({ not .key.starts-with('x-') });
                           set $keys === set()
                       }) {
        for %args.kv -> $k, $v {
            my $normalized-name = (%scalar{$k} // %object{$k})<attr> // $k;
            my $attr = %attr-lookup{$normalized-name};
            if $k (elem) %scalar.keys {
                $attr.set_value(self, $v);
            } elsif $k (elem) %object.keys {
                my $spec = %object{$k};
                my $cond = $spec<array> ?? so $v.map({$_ ~~ $spec<type>}).all !!
                           $spec<hash>  ?? so $v.values.map({$_ ~~ $spec<type>}).all !!
                           $v ~~ $spec<type>;
                if $cond {
                    $attr.set_value(self, $v);
                } else {
                    die X::OpenAPI::Model::TypeMismatch.new(
                        name => ::?CLASS.^name, field => $k,
                        expected => $spec<type>, got => $v);
                }
            }
        }
    }
}
