package Developer::CMS;
use strict;
no warnings 'redefine';
use Time::HiRes;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;
use Hash::Merge::Simple qw/ merge /;
use MT::Util qw( encode_html format_ts offset_time_list encode_url );
use Developer::Util qw( make_zip_archive _dirify app_ref2id _eval compile_test copy_to from_json
                        app_ref2pkg id2app_ref get_app_script utf8_on _trim src2sub src2php );
use File::Temp qw( tempdir );

sub _dashboard_message {
    my ( $cb, $app, $param, $tmpl ) = @_;
    if (! $app->user->is_superuser ) {
        return;
    }
    my $action = $app->param( 'action' );
    if (! $action ) {
        return;
    }
    my $component = MT->component( 'Developer' );
    if ( ref $param eq 'HASH' ) {
        $param->{ system_msg } = 1;
        $param->{ saved } = 1;
    } else {
        my $msg = quotemeta( 'Your Dashboard has been updated.' );
        my $new_message;
        if ( $action eq 'disable_customhandlers' ) {
            $new_message = $component->translate( 'Set status of all Custom Handlers to disabled.' );
        } elsif ( $action eq 'disable_alttemplates' ) {
            $new_message = $component->translate( 'Set status of all Alt Templates to disabled.' );
        } elsif ( $action eq 'disable_mtstudio' ) {
            $new_message = $component->translate( 'Set status of all Custom Handlers and Alt Templates to disabled.' );
        }
        if ( $new_message ) {
            $$param =~ s/$msg/$new_message/;
        }
    }
}

sub _create_object {
    my $app = shift;
    if (! $app->user->is_superuser ) {
        return $app->trans_error( 'Permission denied.' );
    }
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse  = 1;
    # TODO :: Required Field Check
    # TODO :: Search APIs
    # TODO :: Blog / Website Scope
    # TODO :: Revisable / Taggable
    # TODO :: Template Tags
    # TODO :: Use CustomField
    my $component = MT->component( 'Developer' );
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'edit_schema.tmpl' );
    my ( $error_message, $temp_object );
    if ( $app->request_method eq 'POST' ) {
        if ( my $_type = $app->param( '_type' ) ) {
            if (! $app->validate_magic ) {
                return $app->trans_error( 'Permission denied.' );
            }
            my $mode_export;
            if ( $_type eq 'export_object_plugin' ) {
                $mode_export = 1;
            }
            my $saved_object = {};
            my @saved_schema;
            my $class_label = $app->param( 'class_label' );
            my $menu_order = $app->param( 'menu_order' ) || 500;
            $menu_order =~ s/[^0-9]//g;
            $menu_order = '500' unless $menu_order;
            my $error = 0;
            my $audit = $app->param( 'audit' );
            my @column_keys;
            my $plugin_id = $app->param( 'plugin_id' );
            $plugin_id =~ s/[^a-zA-Z0-9]//g;
            $plugin_id = _dirify( $plugin_id );
            $plugin_id = __sanitize_short( $plugin_id );
            my $module_id = $app->param( 'module_id' );
            $module_id =~ s/[^a-zA-Z0-9]//g;
            $module_id = _dirify( $module_id );
            $module_id = __sanitize_short( $module_id );
            my $datasource = lc( $module_id );
            if ( $plugin_id !~ /^[a-zA-Z0-9]{1,}$/ || length( $plugin_id ) > 25 ) {
                $error = 1;
                return $app->error( __trigger_error( $error, $plugin_id ) ) if $mode_export;
            }
            if ( $plugin_id !~ /^[a-zA-Z]{1,}/ ) {
                $error = 1;
                return $app->error( __trigger_error( $error, $plugin_id ) ) if $mode_export;
            }
            if ( $module_id !~ /^[a-zA-Z0-9]{1,}$/ || length( $module_id ) > 25 ) {
                $error = 1;
                return $app->error( __trigger_error( $error, $module_id ) ) if $mode_export;
            }
            if ( $plugin_id !~ /^[a-zA-Z]{1,}/ ) {
                $error = 1;
                return $app->error( __trigger_error( $error, $module_id ) ) if $mode_export;
            }
            if ( MT->model( $datasource ) ) {
                $error = 5;
                return $app->error( __trigger_error( $error, $datasource ) ) if $mode_export;
            }
            if ( MT->component( $plugin_id ) ) {
                $error = 2;
                return $app->error( __trigger_error( $error, $plugin_id ) ) if $mode_export;
            }
            if ( ( lc( $plugin_id ) eq 'core' ) || ( lc( $plugin_id ) eq 'mt' ) ) {
                $error = 2;
                return $app->error( __trigger_error( $error, $plugin_id ) ) if $mode_export;
            }
            my $has_listing = $app->param( 'has_listing' );
            my $class_label_plural = $app->param( 'class_label_plural' );
            my $class_l_label = $app->param( 'class_l_label' );
            my $class_l_label_plural = $app->param( 'class_l_label_plural' );
            # return $plugin_id . '::' . $module_id;
            my $q = $app->param;
            my $column_defs = {};
            my $indexes = {};
            my $lexicon = {};
            my ( $has_lexicon, $primary, $default_sort_key, $blog_child );
            $column_defs->{ id } = 'integer not null auto_increment';
            # my @column_keys;
            my @list_keys;
            my $not_list_keys;
            for my $key( $q->param ) {
                if ( $key =~ m/^column_name_([0-9]{1,})$/ ) {
                    my $row = {};
                    my $num = $1;
                    my $name = $app->param( 'column_name_' . $num );
                    next unless $name;
                    $name = __sanitize_column( $name );
                    next unless $name;
                    if ( $app->param( 'column_list_' . $num ) ) {
                        if ( ( $name eq 'title' ) || ( $name eq 'label' ) || ( $name eq 'name' ) ) {
                            $primary = $name;
                        }
                    }
                    push ( @column_keys, $name );
                    my $type = $app->param( 'column_type_' . $num );
                    if ( ( $name eq 'blog_id' ) && ( $type eq 'integer' ) ) {
                        $blog_child = 1;
                    }
                    my $size;
                    my $length = $app->param( 'column_length_' . $num );
                    if ( $length ) {
                        $length =~ s/[^0-9]//g;
                    }
                    if ( ( $type eq 'string' ) && (! $length ) ) {
                        $length = '255';
                    }
                    if ( ( $type eq 'string' ) && $length ) {
                        $type .= '(' . $length . ')';
                    }
                    if ( $type =~ m/^(.*)\(([0-9]{1,})\)$/ ) {
                        $type = $1;
                        $size = $2;
                    }
                    my $index = $app->param( 'column_index_' . $num );
                    my $label = $app->param( 'column_label_' . $num );
                    my $is_list = $app->param( 'column_list_' . $num );
                    if ( $is_list ) {
                        push ( @list_keys, $name );
                    } else {
                        if ( ( $type eq 'string' ) || ( $type eq 'text' ) ) {
                            if ( $label ) {
                                $not_list_keys->{ $name } = $label;
                            }
                        }
                    }
                    my $l_label = $app->param( 'column_l_label_' . $num );
                    my $not_null = $app->param( 'column_not_null_' . $num );
                    $row = { name => $name,
                             index => $index,
                             label => $label,
                             l_label => $l_label,
                             not_null => $not_null,
                             list => $is_list,
                             type => __type2index( $type ),
                             length => $size };
                    push( @saved_schema, $row );
                    # $type .= ' not null';
                    if ( $size || $label || $not_null ) {
                        my $types = {};
                        $types->{ type } = $type;
                        $types->{ size } = $size if $size;
                        $types->{ label } = $label if $label;
                        $types->{ not_null } = 1 if $not_null;
                        $column_defs->{ $name } = $types;
                    } else {
                        $column_defs->{ $name } = $type;
                    }
                    if ( $index ) {
                        if ( $type ne 'text' ) {
                            $indexes->{ $name } = 1;
                        }
                    }
                    if ( $label && $l_label ) {
                        $lexicon->{ $label } = $l_label;
                        $has_lexicon = 1;
                    }
                }
            }
            if ( ( scalar @list_keys ) == 0 ) {
                $has_listing = 0;
            }
            if (! $primary ) {
                $primary = $list_keys[ 0 ];
            }
            if ( $audit ) {
                $default_sort_key = 'modified_on';
            } else {
                $default_sort_key = 'id';
            }
            my %param;
            my $cols = _trim( __indent( __indent( Dumper( $column_defs ) ) ) );
            $cols =~ s/\n\}$/\n    }/;
            my $list_propaties = {};
            if ( $audit ) {
                # created_on, created_by, modified_on, modified_by
                $column_defs->{ created_on } = { type => 'datetime', label => 'Date Created' };
                $column_defs->{ modified_on } = { type => 'datetime', label => 'Date Modified' };
                push ( @list_keys, 'created_on' );
                push ( @list_keys, 'modified_on' );
            }
            my $primary_html;
            if ( scalar @list_keys ) {
                $list_propaties->{ $datasource }->{ id } = {
                    label => 'ID',
                    base => '__virtual.id',
                    display => 'option',
                    order => 1,
                };
                my $order = 0;
                for my $key ( @list_keys ) {
                    $order++;
                    if ( $primary && ( $key eq $primary ) ) {
                        my $label = $column_defs->{ $key }->{ label };
                        $label = lcfirst( $key ) unless $label;
                        $list_propaties->{ $datasource }->{ $key } = {
                            label => $label,
                            base => '__virtual.title',
                            display => 'force',
                            order => 2,
                        };
                        $primary_html = <<MTML;
>-
                sub {
                    my ( \$prop, \$obj, \$app ) = \@_;
                    my \$url = \$app->uri( mode => 'view',
                                         args => { _type => '${datasource}',
                                                   id => \$obj->id } );
                    my \$name = MT::Util::encode_html( \$obj->${key} );
                    if (! \$name ) {
                        \$name = '[Id:' . \$obj->id . ']';
                    }
                    return "<a href=\\"\${url}\\">\${name}</a>";
                }
MTML
                        chomp( $primary_html );
                        $list_propaties->{ $datasource }->{ $key }->{ html } = '__PRIMARY__';
                    } else {
                        my $col = $column_defs->{ $key };
                        my ( $label, $type );
                        if ( ( ref $col ) eq 'HASH' ) {
                            $label = $col->{ label };
                            $type = $col->{ type };
                        } else {
                            $label = lcfirst( $key );
                            $type = $col;
                        }
                        if ( $type eq 'datetime' ) {
                            $list_propaties->{ $datasource }->{ $key } = {
                                label => $label,
                                base => '__virtual.created_on',
                                display => 'optional',
                                order => $order * 10,
                            };
                        } else {
                            $list_propaties->{ $datasource }->{ $key } = {
                                label => $label,
                                base => '__virtual.id',
                                display => 'optional',
                                order => $order * 10,
                            };
                        }
                    }
                }
                if ( $audit ) {
                    $order++;
                    $list_propaties->{ $datasource }->{ created_by } = {
                        label => 'Created by',
                        base => '__virtual.author_name',
                        display => 'optional',
                        order => $order * 10,
                    };
                    $order++;
                    $list_propaties->{ $datasource }->{ modified_by } = {
                        label => 'Modified by',
                        base => '__virtual.author_name',
                        display => 'optional',
                        order => $order * 10,
                    };
                }
                for my $key ( keys %$not_list_keys ) {
                    $list_propaties->{ $datasource }->{ $key } = {
                        label => $not_list_keys->{ $key },
                        base => '__virtual.string',
                        display => 'none',
                    };
                }
            }
            my $propaties = {};
            $propaties->{ list_properties } = $list_propaties;
            my $props = MT::Util::YAML::Dump( $propaties );
            $props =~ s/^\-{1,}//;
            $props = _trim( __indent( $props ) );
            $props =~ s/__PRIMARY__/$primary_html/;
            $param{ column_defs } = $cols;
            $param{ menu_order } = $menu_order;
            my $idx = _trim( __indent( __indent( Dumper( $indexes ) ) ) );
            $idx =~ s/\n\}$/\n    }/;
            $param{ indexes } = $idx;
            $param{ datasource } = $datasource;
            $param{ plugin_id } = $plugin_id;
            $param{ module_id } = $module_id;
            $param{ audit } = $audit;
            if ( $class_label ) {
                $class_label = _trim( Dumper( $class_label ) );
                $param{ class_label } = $class_label;
                $class_label =~ s/^'//;
                $class_label =~ s/'$//;
                if ( $class_l_label ) {
                    $class_l_label = _trim( Dumper( $class_l_label ) );
                    $class_l_label =~ s/^'//;
                    $class_l_label =~ s/'$//;
                }
            }
            if ( $class_label_plural ) {
                $class_label_plural = _trim( Dumper( $class_label_plural ) );
                $param{ class_label_plural } = $class_label_plural;
                $class_label_plural =~ s/^'//;
                $class_label_plural =~ s/'$//;
                if ( $class_l_label_plural ) {
                    $class_l_label_plural = _trim( Dumper( $class_l_label_plural ) );
                    $class_l_label_plural =~ s/^'//;
                    $class_l_label_plural =~ s/'$//;
                }
            }
            if ( $class_label && $class_l_label ) {
                $lexicon->{ $class_label } = $class_l_label;
                $has_lexicon = 1;
            }
            if ( $class_label_plural && $class_l_label_plural ) {
                $lexicon->{ $class_label_plural } = $class_l_label_plural;
                $has_lexicon = 1;
            }
            my $yaml = 'name: ' . $plugin_id . "\n";
            my $version_number = $app->param( 'version_number' );
            $version_number = $component->get_config_value( 'developer_plugin_initial_version' )
                 unless $version_number;
            $version_number =~ s/[^0-9\.]//g;
            my $schema_version = $app->param( 'schema_version' );
            $schema_version = $component->get_config_value( 'developer_plugin_initial_version' )
                 unless $schema_version;
            $schema_version =~ s/[^0-9\.]//g;
            $yaml .= 'version: ' . $version_number . "\n" if $version_number;
            $yaml .= 'schema_version: ' . $schema_version . "\n" if $schema_version;
            if ( $has_lexicon ) {
                my $l10n_class = $plugin_id . '::L10N';
                $yaml .= 'l10n_class: ' . $l10n_class . "\n";
            }
            my ( $author_name, $author_link, $description, $description_lang );
            if ( $app->param( 'plugin_author_name' ) ) {
                $author_name = $app->param( 'plugin_author_name' );
            } else {
                $author_name = $component->get_config_value( 'developer_plugin_author_name' );
            }
            if ( $author_name ) {
                $yaml .= "author_name: ${author_name}\n";
            }
            if ( $app->param( 'plugin_author_link' ) ) {
                $author_link = $app->param( 'plugin_author_link' );
            } else {
                $author_link = $component->get_config_value( 'developer_plugin_author_link' );
            }
            if ( $author_link ) {
                $yaml .= "author_link: ${author_link}\n";
            }
            my $description_raw;
            if ( $app->param( 'plugin_description' ) ) {
                $description = $app->param( 'plugin_description' );
                $description = __sanitize_long( $description );
                $saved_object->{ description } = $description;
                $description_raw = $description;
                $description = '<__trans phrase="' . $description . '">';
                $yaml .= "description: ${description}\n";
                $description_lang = $app->param( 'plugin_description_lang' );
            } else {
                # $description = "${orig_name}'s description.";
            }
            if ( $description && $description_lang ) {
                if ( $description_raw ) {
                    $lexicon->{ $description_raw } = $description_lang;
                    $has_lexicon = 1;
                }
            }
            $saved_object->{ description_lang } = $description_lang;
            $saved_object->{ author_name } = $author_name;
            $saved_object->{ author_link } = $author_link;
            $saved_object->{ plugin_id } = $plugin_id;
            $saved_object->{ module_id } = $module_id;
            $saved_object->{ saved_schema } = \@saved_schema;
            $saved_object->{ audit } = $audit;
            $saved_object->{ menu_order } = $menu_order;
            $saved_object->{ class_label } = $class_label;
            $saved_object->{ class_label_plural } = $class_label_plural;
            $saved_object->{ class_l_label } = $class_l_label;
            $saved_object->{ class_l_label_plural } = $class_l_label_plural;
            $saved_object->{ has_listing } = $app->param( 'has_listing' );
            $saved_object->{ language_id } = $app->user->preferred_language;
            $saved_object->{ version_number } = $version_number;
            $saved_object->{ schema_version } = $schema_version;
            my ( $custom_schema, $orig_obj );
            if ( $_type eq 'save_schema' ) {
                if ( my $id = $app->param( 'id' ) ) {
                    $custom_schema = MT->model( 'customschema' )->load( $id )
                    || return $app->trans_error( 'Load failed: [_1]', MT->model( 'customschema' )->class_label );
                    $orig_obj = $custom_schema->clone_all();
                } else {
                    $custom_schema = MT->model( 'customschema' )->new;
                }
                $custom_schema->name( $plugin_id );
                $custom_schema->module_id( $module_id );
                $custom_schema->author( $author_name );
                $custom_schema->label( $class_label );
                $custom_schema->plural( $class_l_label );
                $custom_schema->lang_id( $app->user->preferred_language );
                $custom_schema->pluginver( $version_number );
                $custom_schema->schemaver( $schema_version );
                $custom_schema->haslist( $app->param( 'has_listing' ) );
            }
            # TODO Save object to database.
            $yaml .= 'object_types:' . "\n";
            $yaml .= '    ' . $datasource . ": ${plugin_id}::${module_id}\n";
            my $obj_type_orig = quotemeta( 'object_types:' . "\n" . '    ' . $datasource . ": ${plugin_id}::${module_id}" );
            my $obj_type_new = 'object_types:' . "\n" . '    ' . $datasource . ": __PLUGIN_ID::${module_id}";
            my $yaml_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'config_filter_object.tmpl' );
            $param{ primary } = $primary;
            $param{ default_sort_key } = $default_sort_key;
            $param{ has_listing } = $has_listing;
            $param{ object_label } = $class_label;
            $param{ blog_child } = $blog_child;
            $param{ list_properties } = $props;
            if ( $audit ) {
                push ( @column_keys, 'created_on' );
            }
            $param{ column_keys } = join( ' ', @column_keys );
            my $add_yaml = $app->build_page( $yaml_tmpl, \%param );
            $yaml .= $add_yaml;
            my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'your_own_object.tmpl' );
            my $pm = $app->build_page( $tmpl, \%param );
            my $tempdir = $app->config( 'TempDir' );
            $tempdir = tempdir( DIR => $tempdir );
            require MT::FileMgr;
            my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
            __mkpath( $fmgr, $tempdir );
            my $root_dir = File::Spec->catdir( $tempdir, 'mt' );
            my $out_zip = File::Spec->catfile( $tempdir, 'mt.zip' );
            my $plugin_dir = File::Spec->catdir( $root_dir, 'plugins', $plugin_id );
            __mkpath( $fmgr, $plugin_dir );
            my $php_dir = File::Spec->catdir( $plugin_dir, 'php' );
            __mkpath( $fmgr, $php_dir );
            my $lib_dir = File::Spec->catdir( $plugin_dir, 'lib', $plugin_id );
            __mkpath( $fmgr, $lib_dir );
            if ( my $e = _eval( $pm ) ) {
                $error = 3;
                return $app->error( __trigger_error( $error, $e, $tempdir ) ) if $mode_export;
            }
            my $pm_file = File::Spec->catfile( $lib_dir, $module_id . '.pm' );
            $param{ plugin_id } = '__PLUGIN_ID';
            my $pm2col = $app->build_page( $tmpl, \%param );
            $param{ plugin_id } = $plugin_id;
            $fmgr->put_data( $pm, $pm_file );
            $custom_schema->props( $pm2col ) if $custom_schema;
            my $l10n_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'L10N_pm.tmpl' );
            if ( $has_lexicon ) {
                my $lib_file = File::Spec->catfile( $lib_dir,  'L10N.pm' );
                $pm = $app->build_page( $l10n_tmpl, \%param );
                $pm =~ s/\r\n?/\n/g;
                $pm = _trim( $pm );
                if ( my $e = _eval( $pm ) ) {
                    $error = 3;
                    return $app->error( __trigger_error( $error, $e, $tempdir ) ) if $mode_export;
                }
                $fmgr->put_data( $pm, $lib_file );
                # $custom_schema->localize( $pm ) if $custom_schema;
            }
            if ( $has_lexicon ) {
                my $language = $app->user->preferred_language;
                if ( $language ne 'en_us' ) {
                    my $l10n_dir = File::Spec->catdir( $lib_dir, 'L10N' );
                    __mkpath( $fmgr, $l10n_dir );
                    if ( $has_listing ) {
                        $lexicon->{ 'Create [_1]' } = __get_trans_text( 'Create [_1]' );
                        $lexicon->{ 'Edit [_1]' } = __get_trans_text( 'Edit [_1]' );
                        $lexicon->{ 'Are you sure you want to remove this [_1]?' }
                            = __get_trans_text( 'Are you sure you want to remove this [_1]?' );
                        $lexicon->{ 'Save this [_1] (s)' }
                            = __get_trans_text( 'Save this [_1] (s)' );
                        $lexicon->{ 'Delete this [_1] (x)' }
                            = __get_trans_text( 'Delete this [_1] (x)' );
                        $lexicon->{ 'Created by' } = $component->translate( 'Created by' );
                        $lexicon->{ 'Modified by' } = $component->translate( 'Modified by' );
                    }
                    my $lexicon_json = MT::Util::to_json( $lexicon );
                    $lexicon = __dumper( $lexicon );
                    $lexicon =~ s/^{//;
                    $lexicon =~ s/}$//;
                    $lexicon =~ s/\n$//;
                    $lexicon =~ s/\n\s{12}([^\s]{1})/\n    $1/g;
                    $param{ lexicon } = $lexicon;
                    $param{ my_language_id } = $language;
                    my $l10n_file = File::Spec->catfile( $l10n_dir,  $language . '.pm' );
                    my $pm = $app->build_page( $l10n_tmpl, \%param );
                    if ( my $e = _eval( $pm ) ) {
                        $error = 3;
                        return $app->error( __trigger_error( $error, $e, $tempdir ) ) if $mode_export;
                    }
                    $pm =~ s/\r\n?/\n/g;
                    $pm = _trim( $pm );
                    $fmgr->put_data( $pm, $l10n_file );
                    $custom_schema->lexicon( $lexicon_json ) if $custom_schema;
                }
            }
            my $yaml_file = File::Spec->catfile( $plugin_dir, 'config.yaml' );
            my $tiny = MT::Util::YAML::Load( $yaml );
            if (! $tiny->{ name } ) {
                $error = 4;
                return $app->error( __trigger_error( $error, undef, $tempdir ) ) if $mode_export;
            }
            $fmgr->put_data( $yaml, $yaml_file );
            $yaml =~ s/$obj_type_orig/$obj_type_new/;
            $custom_schema->config( $yaml ) if $custom_schema;
            my $php_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'class_mt_your_own_object_php.tmpl' );
            my $phpm = $app->build_page( $php_tmpl, \%param );
            my $php_file = File::Spec->catfile( $php_dir, 'class.mt_' . $datasource . '.php'  );
            $fmgr->put_data( $phpm, $php_file );
            # $custom_schema->php( $phpm ) if $custom_schema;
            if ( $has_listing ) {
                my $edit_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'edit_own_object.tmpl' );
                $edit_tmpl = $fmgr->get_data( $edit_tmpl );
                $edit_tmpl =~ s/datasource/$datasource/g;
                $edit_tmpl =~ s/Object/$class_label/g;
                __mkpath( $fmgr, File::Spec->catfile( $plugin_dir, 'tmpl' ) );
                my $edit_file = File::Spec->catfile( $plugin_dir, 'tmpl', 'edit_' . $datasource . '.tmpl'  );
                $fmgr->put_data( $edit_tmpl, $edit_file );
                # TODO
                # $custom_schema->config( $edit_tmpl ) if $custom_schema;
                my $cms_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'object_cms_pm.tmpl' );
                my $cms_pm = $app->build_page( $cms_tmpl, \%param );
                $cms_pm =~ s/<_mt/<mt/g;
                my $cms_file = File::Spec->catfile( $lib_dir, 'CMS.pm' );
                $fmgr->put_data( $cms_pm, $cms_file );
                $param{ plugin_id } = '__PLUGIN_ID';
                # my $cms_pm2col = $app->build_page( $cms_tmpl, \%param );
                $param{ plugin_id } = $plugin_id;
                # $custom_schema->cms( $cms_pm2col ) if $custom_schema;
            }
            if ( $_type eq 'export_object_plugin' ) {
                return __download_zip( $app, $tempdir, $out_zip );
                # my $res = make_zip_archive( $tempdir, $out_zip );
                # $app->{ no_print_body } = 1;
                # my $basename = File::Basename::basename( $out_zip );
                # $app->set_header( 'Content-Disposition' => "attachment; filename=$basename" );
                # $app->set_header( 'Pragma' => '' );
                # $app->send_http_header( 'application/zip' );
                # if ( open( my $fh, '<', $out_zip ) ) {
                #     binmode $fh;
                #     my $data;
                #     while ( read $fh, my ( $chunk ), 8192 ) {
                #         $data .= $chunk;
                #         $app->print( $chunk );
                #     }
                #     close $fh;
                # }
            } else {
                my $custom_schema_id = $custom_schema->id;
                $custom_schema_id = 0 unless $custom_schema_id;
                if ( my $red = MT->model( 'customschema' )->load( { name => $custom_schema->name,
                                                                    id => { not => $custom_schema_id } } ) ) {
                    $error = 2;
                }
                if ( my $red = MT->model( 'customschema' )->load( { module_id => $custom_schema->module_id,
                                                                    id => { not => $custom_schema_id } } ) ) {
                    $error = 5;
                }
                $custom_schema->schema( MT::Util::to_json( $saved_object ) );
                if ( $error ) {
                    $error_message = __trigger_error( $error, $custom_schema->name, $tempdir );
                    $temp_object = $custom_schema;
                } else {
                    $app->run_callbacks( 'cms_pre_save.customschema', $app, $custom_schema, $orig_obj );
                    $custom_schema->save or die $custom_schema->errstr;
                    my $message;
                    if ( defined $orig_obj ) {
                        $message = $component->translate( '[_1] \'[_2]\' (ID:[_3]) edited by \'[_4]\'',
                            $custom_schema->class_label, utf8_on( $custom_schema->name ),
                            $custom_schema->id, $app->user->name );
                    } else {
                        $message = $component->translate( '[_1] \'[_2]\' (ID:[_3]) created by \'[_4]\'',
                            $custom_schema->class_label, utf8_on( $custom_schema->name ),
                            $custom_schema->id, $app->user->name );
                    }
                    $app->log( {
                        message => $message,
                        author_id => $app->user->id,
                        class => 'Custom Schema',
                        level => MT::Log::INFO(),
                    } );
                    $app->run_callbacks( 'cms_post_save.customschema', $app, $custom_schema, $orig_obj );
                    my $return_url = $app->uri . $app->uri_params( mode => 'create_your_own_object',
                                    args => { blog_id => 0, saved => 1, id => $custom_schema->id });
                    return $app->redirect( $return_url );
                }
            }
            File::Path::rmtree( [ $tempdir ] );
            if (! $temp_object ) {
                return;
            }
        }
    }
    my %param;
    my $id = $app->param( 'id' );
    if ( $id || $temp_object ) {
        $param{ id } = $id;
        my $custom_schema = $temp_object;
        if (! $temp_object ) {
            $custom_schema = MT->model( 'customschema' )->load( $id )
            || return $app->trans_error( 'Load failed: [_1]', MT->model( 'customschema' )->class_label );
        }
        my $json = $custom_schema->schema;
        if ( $json ) {
            $json = from_json( $json );
            for my $key ( keys %$json ) {
                if ( $key ne 'saved_schema' ) {
                    $param{ $key } = $json->{ $key };
                } else {
                    my $saved_schema = $json->{ $key };
                    my @schemas = reverse( @$saved_schema );
                    $param{ $key } = \@schemas;
                }
            }
        }
        if ( $error_message ) {
            $param{ 'error' } = $error_message;
        }
        # return Dumper $json;
    } else {
        $param{ author_name } = $component->get_config_value( 'developer_plugin_author_name' );
        $param{ author_link } = $component->get_config_value( 'developer_plugin_author_link' );
        $param{ version_number } = $component->get_config_value( 'developer_plugin_initial_version' );
    }
    $param{ saved } = $app->param( 'saved' );
    return $app->build_page( $tmpl, \%param );
}

sub _export_plugin_popup {
    my $app = shift;
    if (! $app->user->is_superuser ) {
        return $app->trans_error( 'Permission denied.' );
    }
    my $component = MT->component( 'Developer' );
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'export_plugin_popup.tmpl' );
    my %param;
    return $app->build_page( $tmpl, \%param );
}

sub __type2index {
    my $type = shift;
    return 0 if $type eq 'string';
    return 1 if $type eq 'integer';
    return 2 if $type eq 'smallint';
    return 3 if $type eq 'float';
    return 4 if $type eq 'text';
    return 5 if $type eq 'datetime';
    return 6 if $type eq 'boolean';
}

sub __get_trans_text {
    my $key = shift;
    my $component = MT->component( 'Developer' );
    my $new = $component->translate( $key, '[1]' );
    $new =~ s/\[/[_/;
    return $new;
}

sub _export_studio_player {
    my $app = shift;
    my $component = MT->component( 'Developer' );
    if (! $app->user->is_superuser ) {
        return $app->trans_error( 'Permission denied.' );
    }
    if (! $app->validate_magic ) {
        return $app->trans_error( 'Permission denied.' );
    }
    my $block_tags = $component->registry( 'tags', 'block' );
    my $function_tags = $component->registry( 'tags', 'function' );
    my $global_modifiers = $component->registry( 'tags', 'modifier' );
    my $registry = {};
    my $tags = {};
    my $plugin_id = 'StudioPlayer';
    my $key = lc( $plugin_id );
    my $name = 'MT Studio Player';
    my $ref = quotemeta( '$developer::Developer' );
    for my $tag ( keys %$block_tags ) {
        if ( $tag !~ /^App/ ) {
            my $hdlr = $block_tags->{ $tag };
            $hdlr =~ s/^$ref/$plugin_id/;
            $tags->{ block }->{ $tag } = $hdlr;
        }
    }
    for my $tag ( keys %$function_tags ) {
        if ( $tag ne 'DeveloperScript' ) {
            if ( ( $tag !~ /^MLJob/ ) && ( $tag !~ /^CustomHandler/ ) ) {
                my $hdlr = $function_tags->{ $tag };
                $hdlr =~ s/^$ref/$plugin_id/;
                $tags->{ function }->{ $tag } = $hdlr;
            }
        }
    }
    for my $tag ( keys %$global_modifiers ) {
        my $hdlr = $global_modifiers->{ $tag };
        $hdlr =~ s/^$ref/$plugin_id/;
        $tags->{ modifier }->{ $tag } = $hdlr;
    }
    $registry->{ tags } = $tags;
    $registry->{ object_types }->{ property } = $plugin_id . '::Property';
    my $version = $component->registry( 'version' );
    my $schema_version = $component->registry( 'schema_version' );
    my $author_name = $component->registry( 'author_name' );
    my $author_link = $component->registry( 'author_link' );
    my $l10n_class = $plugin_id . '::L10N';
    my $description = '<__trans phrase="Helper Plugin for MT Studio.">';
    my $meta = "name: ${name}\nid:   ${plugin_id}\nkey:  ${key}\ndescription: ${description}\n"
    . "version: ${version}\nschema_version: ${schema_version}\nl10n_class: ${l10n_class}";
    my @configs = qw( AllowPerlScript AllowThrowSQL AllowCreateObject OnetimeTokenTTL
                      PathToRelative SpeedMeterDebugScope ForceTargetOutLink );
    my $config_settings = $component->registry( 'config_settings' );
    for my $key ( keys %$config_settings ) {
        if ( grep( /^$key$/, @configs ) ) {
            my $cfg = $config_settings->{ $key };
            $registry->{ config_settings }->{ $key } = { default => $cfg->{ default },
                                                         updatable => $cfg->{ updatable } };
        }
    }
    $registry->{ config_settings }->{ TranslateComponent } = { default => $plugin_id,
                                                               updatable => 1 } ;
    my $yaml = MT::Util::YAML::Dump( $registry );
    $yaml =~ s/^\-{1,}//;
    $yaml = $meta . $yaml;
    my $tempdir = $app->config( 'TempDir' );
    $tempdir = tempdir( DIR => $tempdir );
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    __mkpath( $fmgr, $tempdir );
    my $root_dir = File::Spec->catdir( $tempdir, 'mt' );
    my $out_zip = File::Spec->catfile( $tempdir, 'mt.zip' );
    my $plugin_dir = File::Spec->catdir( $root_dir, 'plugins', $plugin_id );
    __mkpath( $fmgr, $plugin_dir );
    my $php_dir = File::Spec->catdir( $plugin_dir, 'php' );
    __mkpath( $fmgr, $php_dir );
    my $lib_dir = File::Spec->catdir( $plugin_dir, 'lib', $plugin_id );
    __mkpath( $fmgr, $lib_dir );
    my $l10n_dir = File::Spec->catdir( $lib_dir, 'L10N' );
    __mkpath( $fmgr, $l10n_dir );
    my $yaml_file = File::Spec->catfile( $plugin_dir, 'config.yaml' );
    $yaml = __indent( $yaml );
    $fmgr->put_data( $yaml, $yaml_file );
    my $prop = File::Spec->catfile( $component->path, 'lib', 'Developer', 'Property.pm' );
    $prop = $fmgr->get_data( $prop );
    $prop =~ s/Developer/$plugin_id/g;
    my $prop_file = File::Spec->catfile( $plugin_dir, 'lib', $plugin_id, 'Property.pm' );
    $fmgr->put_data( $prop, $prop_file );
    my $tags_pm = File::Spec->catfile( $component->path, 'lib', 'Developer', 'Tags.pm' );
    $tags_pm = $fmgr->get_data( $tags_pm );
    $tags_pm =~ s/Developer/$plugin_id/g;
    $tags_pm =~ s/developer/$key/g;
    my $rem_tag = quotemeta( 'sub _hdlr_ml_job' );
    my $rem_tag_end = quotemeta( "\n}\n\n" );
    $tags_pm =~ s/$rem_tag.*?$rem_tag_end//sg;
    my $export = quotemeta( 'StudioPlayer::Util' );
    $tags_pm =~ s/$export/Developer::Util/;
    my $tags_file = File::Spec->catfile( $plugin_dir, 'lib', $plugin_id, 'Tags.pm' );
    $fmgr->put_data( $tags_pm, $tags_file );
    my $util = File::Spec->catfile( $component->path, 'lib', 'Developer', 'Util.pm' );
    $util = $fmgr->get_data( $util );
    # $util =~ s/Developer/$plugin_id/g;
    # $util =~ s/developer/$key/g;
    my $rem_sub = quotemeta( 'sub compile_test {' );
    my $rem_sub_end = "\n}\n\n";
    $util =~ s/$rem_sub.*?$rem_sub_end//s;
    $util =~ s/compile_test//s;
    __mkpath( $fmgr, File::Spec->catdir( $plugin_dir, 'lib', 'Developer' ) );
    my $util_file = File::Spec->catfile( $plugin_dir, 'lib', 'Developer', 'Util.pm' );
    $fmgr->put_data( $util, $util_file );
    my $l10n = File::Spec->catfile( $component->path, 'lib', 'Developer', 'L10N.pm' );
    $l10n = $fmgr->get_data( $l10n );
    $l10n =~ s/Developer/$plugin_id/g;
    my $l10n_file = File::Spec->catfile( $plugin_dir, 'lib', $plugin_id, 'L10N.pm' );
    $fmgr->put_data( $l10n, $l10n_file );
    my $lang = $app->user->preferred_language;
    my $lang_file = File::Spec->catfile( $component->path, 'tmpl', 'helper_' . $lang . '_pm.tmpl' );
    if ( $fmgr->exists( $lang_file ) ) {
        $lang_file = $fmgr->get_data( $lang_file );
        $lang_file =~ s/Developer/$plugin_id/g;
        $lang_file =~ s/developer/$key/g;
        my $lang_file_out = File::Spec->catfile( $plugin_dir, 'lib', $plugin_id, 'L10N', $lang . '.pm' );
        $fmgr->put_data( $lang_file, $lang_file_out );
    }
    copy_to( File::Spec->catdir( $component->path, 'php' ), File::Spec->catdir( $plugin_dir, 'php' ) );
    my $tmp = File::Spec->catdir( $plugin_dir, 'php', 'tmpl' );
    File::Path::rmtree( [ $tmp ] );
    my @rem = qw( class.mt_mtmljob.php init.Job.php mt-preview-tag.php );
    for my $r ( @rem ) {
        $r = File::Spec->catdir( $plugin_dir, 'php', $r );
        $fmgr->delete( $r );
    }
    @rem = qw( function.mtcustomhandler.php function.mtcustomhandlername.php function.mtcustomhandlertitle.php
               function.mtmljobname.php function.mtmljob.php function.mtmljobtitle.php );
    for my $r ( @rem ) {
        $r = File::Spec->catdir( $plugin_dir, 'php', ,'tags', $r );
        $fmgr->delete( $r );
    }
    my $cfg = File::Spec->catdir( $plugin_dir, 'php', 'config.php' );
    my $cfg_php = $fmgr->get_data( $cfg );
    $cfg_php =~ s/Developer/$plugin_id/g;
    $cfg_php =~ s/developer/$key/g;
    my $start = quotemeta( '//Start not export' );
    my $end = quotemeta( '//End not export' );
    $cfg_php =~ s/$start.*?$end//sg;
    $fmgr->put_data( $cfg_php, $cfg );
    my $scp = File::Spec->catdir( $plugin_dir, 'php', 'tags', 'function.mtdeveloperscript.php' );
    $fmgr->delete( $scp );
    $scp = File::Spec->catdir( $plugin_dir, 'php', 'tags', 'function.mtlog.php' );
    my $scp_php = $fmgr->get_data( $scp );
    $scp_php =~ s/Developer/$plugin_id/g;
    $scp_php =~ s/developer/$key/g;
    $fmgr->put_data( $scp_php, $scp );
    return __download_zip( $app, $tempdir, $out_zip );
    # my $res = make_zip_archive( $tempdir, $out_zip );
    # $app->{ no_print_body } = 1;
    # my $basename = File::Basename::basename( $out_zip );
    # $app->set_header( 'Content-Disposition' => "attachment; filename=$basename" );
    # $app->set_header( 'Pragma' => '' );
    # $app->send_http_header( 'application/zip' );
    # if ( open( my $fh, '<', $out_zip ) ) {
    #     binmode $fh;
    #     my $data;
    #     while ( read $fh, my ( $chunk ), 8192 ) {
    #         $data .= $chunk;
    #         $app->print( $chunk );
    #     }
    #     close $fh;
    # }
    # File::Path::rmtree( [ $tempdir ] );
    # return;
}

sub _recover_developer {
    my $app = shift;
    if (! $app->user->is_superuser ) {
        return $app->trans_error( 'Permission denied.' );
    }
    my $component = MT->component( 'Developer' );
    my $password = $component->get_config_value( 'developer_recover_password' );
    my $pass = $app->param( 'password' ) || '';
    if ( $pass ne $password ) {
        return $app->trans_error( 'Passwords do not match.' );
    }
    my $mode = $app->mode;
    my @objects;
    if ( $mode eq 'disable_customhandlers' ) {
        @objects = MT->model( 'mtmljob' )->load( { status => 2 } );
    } elsif ( $mode eq 'disable_alttemplates' ) {
        @objects = MT->model( 'alttemplate' )->load( { status => 2 } );
    } else {
        @objects = MT->model( 'mtmljob' )->load( { status => 2 } );
        my @objects2 = MT->model( 'alttemplate' )->load( { status => 2 } );
        push( @objects, @objects2 );
    }
    for my $obj( @objects ) {
        $obj->status( 1 );
        $obj->save or die $obj->errstr;
    }
    my $mt = MT->instance;
    $mt->reboot;
    $app->return_to_dashboard( 'action' => $mode );
    return 1;
}

sub _throw_sql {
    my $app = shift;
    if (! $app->instance->config( 'AllowThrowSQL' ) ) {
        return $app->trans_error( 'Permission denied.' );
    }
    my $component = MT->component( 'Developer' );
    if (! $app->user->is_superuser ) {
        return $app->trans_error( 'Permission denied.' );
    }
    if ( $app->request_method eq 'POST' ) {
        if (! $app->validate_magic ) {
            return $app->trans_error( 'Permission denied.' );
        }
    }
    my %param;
    if ( my $type = $app->param( '_type' ) ) {
        if ( $type eq 'sql' ) {
            my $query = $app->param( 'sql_request' );
            $param{ sql_request } = $query;
            require MT::Object;
            my $start = Time::HiRes::time();
            my $driver = MT::Object->driver;
            my $dbh = $driver->{ fallback }->{ dbh };
            my $sth = $dbh->prepare( $query );
            return $app->trans_error( "Error in query: " . $dbh->errstr ) if $dbh->errstr;
            my $do = $sth->execute();
            return $app->trans_error( "Error in query: " . $sth->errstr ) if $sth->errstr;
            my @row;
            my @next_row;
            my $columns = $sth->{ NAME_hash };
            @next_row = $sth->fetchrow_array();
            while ( @next_row ) {
                push ( @row, @next_row );
                @next_row = $sth->fetchrow_array();
            }
            $sth->finish();
            my $end = Time::HiRes::time();
            my $time = $end - $start;
            my $res;
            if ( @row ) {
                $res = Dumper @row;
            } else {
                $res = Dumper $do;
            }
            Encode::_utf8_on( $res );
            $param{ processing_time } = $time;
            $param{ page_msg } = $res;
        }
    }
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'throw_sql.tmpl' );
    return $app->build_page( $tmpl, \%param );
}

sub _mtmljob_export_plugin {
    my $app = shift;
    my $author = $app->user;
    if ( $author->is_superuser ) {
        $app->validate_magic
            or return $app->errtrans( 'Invalid request.' );
    } else {
        $app->return_to_dashboard( permission => 1 );
        return;
    }
    my $component = MT->component( 'Developer' );
    my $out = $app->param( 'export_text' );
    my $tagkind = $app->param( 'export_tagkind' );
    my $plugin_id = $app->param( 'export_plugin_id' );
    if (! $plugin_id ) {
        $plugin_id = $app->param( 'plugin_id' );
    }
    my $text_php = $app->param( 'export_text_php' );
    my $priority = $app->param( 'export_priority' );
    my $app_ref = $app->param( 'export_app_ref' );
    my $detail = $app->param( 'export_detail' );
    my $is_default = $app->param( 'export_is_default' );
    my $basename = $app->param( 'export_basename' );
    if (! $basename ) {
        return $app->trans_error( $component->translate( 'A Custom Handler\'s basename is required.' ) );
    }
    my $interval = $app->param( 'export_interval' );
    my $evalscript = $app->param( 'export_evalscript' );
    my $title = $app->param( 'export_title' );
    my $nextrun_on = $app->param( 'export_nextrun_on' );
    if ( $interval && ( $interval > 7 ) ) {
        $priority = '';
    }
    if ( $nextrun_on ) {
        $nextrun_on =~ s/[^0-9]//g;
    }
    my $requires_login = $app->param( 'export_requires_login' );
    my $job = MT->model( 'mtmljob' )->new;
    $job->title( $title );
    $job->nextrun_on( $nextrun_on );
    $job->text( $out );
    $job->text_php( $text_php );
    $job->priority( $priority );
    $job->app_ref( $app_ref );
    $job->requires_login( $requires_login );
    $job->evalscript( $evalscript );
    $job->tagkind( $tagkind );
    $job->detail( $detail );
    $job->basename( $basename );
    $job->interval( $interval );
    $job->is_default( $is_default );
    if ( my $id = $app->param( 'id' ) ) {
        $job->{ return_args } = '__mode=view&_type=mtmljob&id=' . $id;
    }
    return _mtmljobs_to_plugin( $app, $job, $plugin_id );
}

sub _export_plugin_confirm {
    my ( $app, $plugin_id, $plugin_name, $jobs ) = @_;
    my $list_action = 1;
    if ( ( scalar @$jobs ) == 1 ) {
        my $job = @$jobs[ 0 ];
        if (! $job->id ) {
            $list_action = 0;
        }
    }
    my $component = MT->component( 'Developer' );
    my %param;
    $param{ list_action } = $list_action;
    $param{ plugin_id } = $plugin_id;
    $param{ plugin_name } = $plugin_name;
    $param{ plugin_author_name } = $component->get_config_value( 'developer_plugin_author_name' );
    $param{ plugin_author_link } = $component->get_config_value( 'developer_plugin_author_link' );
    $param{ plugin_version } = $component->get_config_value( 'developer_plugin_initial_version' );
    # $param{ plugin_description } = "${plugin_name} description.";
    # $param{ plugin_description_lang } = $component->translate( '[_1] description.', $plugin_name );
    # $param{ plugin_task_label } = "${plugin_name} task";
    # $param{ plugin_task_label_lang } = $component->translate( '[_1] task', $plugin_name );
    my $include_task;
    my @job_loop;
    $param{ return_args } = '__mode=list&_type=mtmljob&blog_id=0';
    for my $job( @$jobs ) {
        if ( $job->interval < 7 ) {
            $include_task = 1;
        }
        my $cols = $job->column_values;
        $cols->{ interval_text } = $job->interval_text_short;
        $cols->{ interval_text_full } = $job->interval_text;
        push( @job_loop, $cols );
        if ( my $return_args = $job->{ return_args } ) {
            $param{ return_args } = $return_args;
        }
    }
    $param{ job_loop } = \@job_loop;
    $param{ include_task } = $include_task;
    $param{ screen_group } = 'mtmljob';
    $param{ search_label } = $component->translate( 'Custom Handler' );
    $param{ search_type }  = 'mtmljob';
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'export_confirm.tmpl' );
    return $app->build_page( $tmpl, \%param );
}

sub _customschemas_to_plugin {
    my $app = shift;
    if ( $app->user->is_superuser ) {
        $app->validate_magic
            or return $app->errtrans( 'Invalid request.' );
    } else {
        $app->return_to_dashboard( permission => 1 );
        return;
    }
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse  = 1;
    my $component = MT->component( 'Developer' );
    my $plugin_id = $app->param( 'itemset_action_input' );
    my $orig_name;
    if (! $plugin_id ) {
        $plugin_id = $app->param( 'plugin_id' );
        $orig_name = $app->param( 'plugin_name' );
    }
    my %param;
    $param{ screen_group } = 'customschema';
    $param{ search_label } = MT->translate( 'Entry' );
    $param{ search_type }  = 'entry';
    $param{ plugin_name }  = $plugin_id;
    $plugin_id = _trim( $plugin_id );
    $orig_name = $plugin_id unless $orig_name;
    $plugin_id =~ s/[^a-zA-Z0-9]//g;
    $plugin_id = _dirify( $plugin_id );
    $orig_name = _trim( $orig_name );
    $orig_name =~ s/[^a-zA-Z0-9\s]{1,}//g;
    $plugin_id =~ s/[^a-zA-Z0-9]//g;
    $plugin_id = _dirify( $plugin_id );
    my $error;
    if ( $plugin_id !~ /^[a-zA-Z0-9]{1,}$/ || length( $plugin_id ) > 25 ) {
        $error = 1;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( $plugin_id !~ /^[a-zA-Z]{1,}/ ) {
        $error = 1;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( MT->model( $plugin_id ) ) {
        $error = 2;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( MT->component( $plugin_id ) ) {
        $error = 2;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( ( lc( $plugin_id ) eq 'core' ) || ( lc( $plugin_id ) eq 'mt' ) ) {
        $error = 2;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    my @ids = $app->param( 'id' );
    my @schemas = MT->model( 'customschema' )->load( { id => \@ids } );
    if ( my $type = $app->param( '_type' ) ) {
        if ( $type eq 'do_export' ) {
            my $lexicon = {};
            my $config = {};
            my $modules = {};
            my $php_modules = {};
            my $has_lexicon;
            for my $s ( @schemas ) {
                my $lid = $s->lang_id;
                if ( $lid && ( $lid eq $app->user->preferred_language ) ) {
                    my $schema = $s->schema;
                    my $orig_desc;
                    if ( $schema ) {
                        $schema = from_json( $schema );
                        $orig_desc = $schema->{ description };
                    }
                    if ( my $l = $s->lexicon ) {
                        $l = from_json( $l );
                        if ( $orig_desc ) {
                            delete( $l->{ $orig_desc } );
                        }
                        $lexicon = merge( $lexicon, $l );
                        $has_lexicon = 1;
                    }
                }
                if ( my $c = $s->config ) {
                    $c = MT::Util::YAML::Load( $c );
                    delete( $c->{ name } );
                    delete( $c->{ description } );
                    delete( $c->{ author_name } );
                    delete( $c->{ author_link } );
                    delete( $c->{ version } );
                    delete( $c->{ schema_version } );
                    delete( $c->{ l10n_class } );
                    $config = merge( $config, $c );
                }
                my $props = $s->props;
                $props =~ s/__PLUGIN_ID/$plugin_id/g;
                $modules->{ $s->module_id } = $props;
            }
            $config = MT::Util::YAML::Dump( $config );
            $config =~ s/^\-{1,}//;
            $config = _trim( __indent( $config ) );
            my $l10n_class = $plugin_id . '::L10N';
            my $key = lc( $plugin_id );
            my $description = $app->param( 'plugin_description' );
            my $description_l = $app->param( 'plugin_description_lang' );
            my $version = $app->param( 'plugin_version' );
            $version = __sanitize_short( $version );
            my $schema_version = $app->param( 'plugin_schema_version' );
            $schema_version = __sanitize_short( $schema_version );
            $description = __sanitize_long( $description ) if $description;
            if ( $description && $description_l ) {
                $description_l = __sanitize_long( $description_l );
                $lexicon->{ $description } = $description_l;
                $has_lexicon = 1;
            }
            $description = '<__trans phrase="' . $description . '">' if $description;
            my $meta = "name: ${orig_name}\nid:   ${plugin_id}\nkey:  ${key}\ndescription: ${description}\n"
            . "version: ${version}\nschema_version: ${schema_version}\nl10n_class: ${l10n_class}\n";
            delete( $lexicon->{ '' } );
            $config = $meta . $config;
            $config =~ s/__PLUGIN_ID/$plugin_id/g;
            my $tempdir = $app->config( 'TempDir' );
            $tempdir = tempdir( DIR => $tempdir );
            require MT::FileMgr;
            my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
            __mkpath( $fmgr, $tempdir );
            my $root_dir = File::Spec->catdir( $tempdir, 'mt' );
            my $out_zip = File::Spec->catfile( $tempdir, 'mt.zip' );
            my $plugin_dir = File::Spec->catdir( $root_dir, 'plugins', $plugin_id );
            __mkpath( $fmgr, $plugin_dir );
            my $php_dir = File::Spec->catdir( $plugin_dir, 'php' );
            __mkpath( $fmgr, $php_dir );
            my $lib_dir = File::Spec->catdir( $plugin_dir, 'lib', $plugin_id );
            __mkpath( $fmgr, $lib_dir );
            my $php_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'class_mt_your_own_object_php.tmpl' );
            my %param;
            $param{ plugin_id } = $plugin_id;
            for my $module_id ( keys %$modules ) {
                my $pm_file = File::Spec->catfile( $lib_dir, $module_id . '.pm' );
                my $pm = $modules->{ $module_id };
                $fmgr->put_data( $pm, $pm_file );
                my $datasource = lc( $module_id );
                $param{ module_id } = $module_id;
                $param{ datasource } = $datasource;
                my $phpm = $app->build_page( $php_tmpl, \%param );
                my $php_file = File::Spec->catfile( $php_dir,  'class.mt_' . $datasource . '.php' );
                $fmgr->put_data( $phpm, $php_file );
            }
            my $l10n_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'L10N_pm.tmpl' );
            my $pm_file = File::Spec->catfile( $lib_dir,  'L10N.pm' );
            my $pm = $app->build_page( $l10n_tmpl, \%param );
            $fmgr->put_data( $pm, $pm_file );
            my $cms_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'object_cms_pm.tmpl' );
            $pm_file = File::Spec->catfile( $lib_dir,  'CMS.pm' );
            $pm = $app->build_page( $cms_tmpl, \%param );
            $fmgr->put_data( $pm, $pm_file );
            if ( $has_lexicon ) {
                my $lang_id = $app->user->preferred_language;
                if ( $lang_id ne 'en_us' ) {
                    my $l10n_dir = File::Spec->catdir( $lib_dir, 'L10N' );
                    __mkpath( $fmgr, $l10n_dir );
                    my $pm_file = File::Spec->catdir( $l10n_dir, $lang_id . '.pm' );
                    $param{ my_language_id } = $lang_id;
                    $lexicon = Dumper $lexicon;
                    $lexicon =~ s/^\{//;
                    $lexicon =~ s/\n\}$//;
                    $param{ lexicon } = $lexicon;
                    my $pm = $app->build_page( $l10n_tmpl, \%param );
                    $fmgr->put_data( $pm, $pm_file );
                }
            }
            my $yaml_file = File::Spec->catdir( $plugin_dir, 'config.yaml' );
            $fmgr->put_data( $config . "\n", $yaml_file );
            return __download_zip( $app, $tempdir, $out_zip );
            # return $plugin_dir;
            # return;
        }
    }
    $param{ plugin_id } = $plugin_id;
    $param{ plugin_name } = $orig_name;
    $param{ export_type } = 'schema';
    $param{ plugin_author_name } = $component->get_config_value( 'developer_plugin_author_name' );
    $param{ plugin_author_link } = $component->get_config_value( 'developer_plugin_author_link' );
    $param{ plugin_version } = $component->get_config_value( 'developer_plugin_initial_version' );
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'export_confirm.tmpl' );
    my @schemas_loop;
    for my $s ( @schemas ) {
        my $cols = $s->column_values;
        my $json = $s->schema;
        if ( $json ) {
            $json = from_json( $json );
            for my $key ( keys %$json ) {
                $cols->{ '_' . $key } = $json->{ $key };
            }
        }
        push( @schemas_loop, $cols );
    }
    $param{ schema_count } = scalar( @schemas_loop );
    $param{ schemas_loop } = \@schemas_loop;
    return $app->build_page( $tmpl, \%param );
}

sub __download_zip {
    my ( $app, $tempdir, $out_zip ) = @_;
    my $res = make_zip_archive( $tempdir, $out_zip );
    $app->{ no_print_body } = 1;
    my $basename = File::Basename::basename( $out_zip );
    $app->set_header( 'Content-Disposition' => "attachment; filename=$basename" );
    $app->set_header( 'Pragma' => '' );
    $app->send_http_header( 'application/zip' );
    if ( open( my $fh, '<', $out_zip ) ) {
        binmode $fh;
        my $data;
        while ( read $fh, my ( $chunk ), 8192 ) {
            $data .= $chunk;
            $app->print( $chunk );
        }
        close $fh;
    }
    File::Path::rmtree( [ $tempdir ] );
    return;
}

sub _mtmljobs_to_plugin {
    my $app = shift;
    my $export_job = shift;
    my $export_plugin_id = shift;
    my $author = $app->user;
    if ( $author->is_superuser ) {
        $app->validate_magic
            or return $app->errtrans( 'Invalid request.' );
    } else {
        $app->return_to_dashboard( permission => 1 );
        return;
    }
    my $component = MT->component( 'Developer' );
    my @ids = $app->param( 'id' );
    my $plugin_id;
    if ( $export_plugin_id ) {
        $plugin_id = $export_plugin_id;
    } else {
        $plugin_id = $app->param( 'itemset_action_input' );
        if (! $plugin_id ) {
            $plugin_id = $app->param( 'plugin_id' );
        }
    }
    my $error = 0;
    $plugin_id = _trim( $plugin_id );
    my $orig_name;
    if ( $app->param( 'plugin_name' ) ) {
        $orig_name = $app->param( 'plugin_name' );
    } else {
        $orig_name = $plugin_id;
    }
    $orig_name = _trim( $orig_name );
    $orig_name =~ s/[^a-zA-Z0-9\s]{1,}//g;
    $plugin_id =~ s/[^a-zA-Z0-9]//g;
    $plugin_id = _dirify( $plugin_id );
    if ( $plugin_id !~ /^[a-zA-Z0-9]{1,}$/ || length( $plugin_id ) > 25 ) {
        $error = 1;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( $plugin_id !~ /^[a-zA-Z]{1,}/ ) {
        $error = 1;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( MT->model( $plugin_id ) ) {
        $error = 2;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( MT->component( $plugin_id ) ) {
        $error = 2;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    if ( ( lc( $plugin_id ) eq 'core' ) || ( lc( $plugin_id ) eq 'mt' ) ) {
        $error = 2;
        return $app->error( __trigger_error( $error, $plugin_id ) );
    }
    my $plugin_key = lc( $plugin_id );
    my @jobs;
    if ( $export_job ) {
        push( @jobs, $export_job );
    } else {
        @jobs = MT->model( 'mtmljob' )->load( { id => \@ids, evalscript => 1,
                                                interval => [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 ] } );
        my @add_jobs = MT->model( 'mtmljob' )->load( { id => \@ids, evalscript => 0,
                                                       interval => { not => 0 } } );
        push @jobs, @add_jobs;
    }
    if (! scalar @jobs ) {
        $app->add_return_arg( not_exported => 1 );
        return $app->call_return;
    }
    if ( (! $app->param( '_type' ) ) || $app->param( '_type' ) ne 'do_export' ) {
        return _export_plugin_confirm( $app, $plugin_id, $orig_name, \@jobs );
    }
    my %param;
    $param{ plugin_id } = $plugin_id;
    my $callbacks = {};
    my $tags = {};
    my $methods = {};
    my $tasks = {};
    my $apps = {};
    my $bootstraps = {};
    my $endpoints = {};
    my $plugin_templates = {};
    my $with_templates;
    my @yamls;
    for my $job ( @jobs ) {
        my $text = $job->text;
        if ( $job->evalscript ) {
            my $mode = 'perl';
            if ( $job->interval != 12 ) {
                $text = src2sub( $text );
                $text =~ s/\n{1,}$//s;
            } else {
                $mode = 'yaml';
            }
            my $error = compile_test( $text, $mode );
            if ( $error ne 'OK' ) {
                return $app->error( __trigger_error( $component->translate( 'An error occurred while trying to require \'[_1]\'', $error ), $plugin_id ) );
            }
        }
        if ( $job->interval == 7 ) {
            # Callbacks
            my $cb_name = $job->detail;
            my @cbs = split( /,/, $cb_name );
            my $basename =  $job->basename;
            $basename = _dirify( $basename );
            if (! $job->evalscript ) {
                my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'method.tmpl' );
                $param{ mtmljob_basename } = $basename;
                $param{ callback } = 1;
                $plugin_templates->{ $basename } = $text;
                $with_templates = 1;
                $text = $app->build_page( $tmpl, \%param );
            }
            for my $cb ( @cbs ) {
                $cb = _trim( $cb );
                my $hdlrs;
                my $priorities;
                if ( $callbacks->{ $cb } ) {
                    $hdlrs = $callbacks->{ $cb }->{ code };
                    $priorities = $callbacks->{ $cb }->{ priority };
                } else {
                    $hdlrs = [];
                    $priorities = [];
                }
                push ( @$hdlrs,  $text );
                push ( @$priorities,  $job->priority );
                $callbacks->{ $cb }->{ code } = $hdlrs;
                $callbacks->{ $cb }->{ priority } = $priorities;
            }
        } elsif ( $job->interval == 12 ) {
            # config.yaml
            my $cfg = $app->param( 'text' );
            my $error = compile_test( $cfg, 'yaml' );
            if ( $error ne 'OK' ) {
                return $app->error( __trigger_error( $component->translate( 'An error occurred while trying to Load config.yaml \'[_1]\'', $error ), $plugin_id ) );
            }
            push ( @yamls, $job );
        } elsif ( $job->interval == 11 ) {
            # DataAPI Endpoints
            my $basename =  $job->basename;
            $basename = _dirify( $basename );
            my $detail = $job->detail;
            my ( $verb, $route ) = split( /,/, $detail );
            if (! $route ) {
                $verb = 'GET';
                $route = $verb;
            }
            my $version = $component->get_config_value( 'developer_data_api_version' ) || 1;
            $version =~ s/[^0-9]//g;
            my $requires_login = $job->requires_login || 0;
            my $endpoint = { id => $basename };
            $endpoint->{ requires_login } = $requires_login;
            $endpoint->{ verb } = _trim( $verb );
            $endpoint->{ route } = _trim( $route );
            $endpoint->{ version } = $version;
            my $handler = '_handler_' . $basename;
            if (! $job->evalscript ) {
                my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'method.tmpl' );
                $param{ mtmljob_basename } = $basename;
                $param{ data_api } = 1;
                $plugin_templates->{ $basename } = $text;
                $with_templates = 1;
                $text = $app->build_page( $tmpl, \%param );
            }
            $text =~ s/^sub/sub $handler/;
            $endpoint->{ handler } = $plugin_id . '::DataAPI::' . $handler;
            $endpoint->{ _handler } = $text;
            $endpoints->{ $basename } = $endpoint;
            # return Dumper $endpoint;
        } elsif ( $job->interval == 8 ) {
            # Tags
            my $tag_name = $job->detail;
            my $handler;
            my $php_handler;
            my $text_php;
            my @handler_loop;
            my $orig_tag = $tag_name;
            $tag_name = lc( $tag_name );
            my $tagkind = $job->tagkind;
            if ( $tagkind ne 'modifier' ) {
                $tag_name =~ s/^mt//i;
                $orig_tag =~ s/^mt//i;
                $handler = '_hdlr_' . $tag_name;
                if ( $tagkind eq 'function' ) {
                    $php_handler = 'smarty_function_mt' . $tag_name;
                } else {
                    $php_handler = 'smarty_block_mt' . $tag_name;
                }
                if ( $tagkind eq 'conditional' ) {
                    $tag_name .= '?';
                }
            } else {
                $handler = '_filter_' . $tag_name;
                $php_handler = 'smarty_modifier_' . $tag_name;
            }
            my $basename =  $job->basename;
            $basename = _dirify( $basename );
            $text_php = $job->text_php;
            if (! $job->evalscript ) {
                my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'tags_php.tmpl' );
                $param{ mtmljob_basename } = $basename;
                $param{ tagkind } = $tagkind;
                $param{ tag_name } = $tag_name;
                $text_php = '    ' . $app->build_page( $tmpl, \%param );
            }
            if ( $text_php !~ m/^function/m ) {
                if ( $tagkind eq 'function' ) {
                    $text_php = "function ${php_handler} ( \$args, &\$ctx ) {\n" .
                    $text_php . "\n}";
                } elsif ( $tagkind eq 'modifier' ) {
                    $text_php = "function ${php_handler} ( \$text, &\$arg ) {\n" .
                    $text_php . "\n}";
                } else {
                    $text_php = "function ${php_handler} ( \$args, \$content, &\$ctx, &\$repeat ) {\n" .
                    $text_php . "\n}";
                }
            } else {
                if ( $tagkind eq 'function' ) {
                    $text_php =~ s/^function[^\{]{0,}/function ${php_handler} ( \$args, &\$ctx ) /;
                } elsif ( $tagkind eq 'modifier' ) {
                    $text_php =~ s/^function[^\{]{0,}/function ${php_handler} ( \$text, \$text ) /;
                } else {
                    $text_php =~ s/^function[^\{]{0,}/function ${php_handler} ( \$args, \$content, &\$ctx, &\$repeat ) /;
                }
            }
            if ( my $php_path = $component->get_config_value( 'developer_php_path' ) ) {
                my $error = compile_test( $text_php, 'php' );
                if ( $error ne 'OK' ) {
                    return $app->error( __trigger_error( $component->translate( 'An error occurred while trying to require \'[_1]\'', $error ), $plugin_id ) );
                }
            }
            if (! $job->evalscript ) {
                my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'tags.tmpl' );
                $param{ mtmljob_basename } = $basename;
                $param{ tagkind } = $tagkind;
                $param{ tag_name } = $tag_name;
                $plugin_templates->{ $basename } = $text;
                $with_templates = 1;
                $text = $app->build_page( $tmpl, \%param );
            }
            $tags->{ $tagkind }->{ $orig_tag } = { perl => $text, php => $text_php };
        } elsif ( $job->interval == 10 ) {
            # Methods
            my $meth_name = $job->detail;
            my $app_ref = $job->app_ref;
            my @split_app = split( /::/, $app_ref );
            my $pm_name = $split_app[ scalar( @split_app ) - 1 ];
            my $app_id = app_ref2id( $app_ref );
            $apps->{ $app_id } = $pm_name;
            my @meths = split( /,/, $meth_name );
            if (! $job->evalscript ) {
                my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'method.tmpl' );
                my $basename =  $job->basename;
                $basename = _dirify( $basename );
                $param{ mtmljob_basename } = $basename;
                $plugin_templates->{ $basename } = $text;
                $with_templates = 1;
                $text = $app->build_page( $tmpl, \%param );
            }
            for my $meth ( @meths ) {
                $meth = _trim( $meth );
                $methods->{ $app_id }->{ $meth }->{ code } = $text;
                $methods->{ $app_id }->{ $meth }->{ requires_login } = $job->requires_login;
            }
        } elsif ( $job->interval == 9 ) {
            # Application
            my $basename = $job->basename;
            $basename = _dirify( $basename );
            my $handler = '_handler_' . $basename;
            if (! $job->evalscript ) {
                my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'method.tmpl' );
                $param{ mtmljob_basename } = $basename;
                $plugin_templates->{ $basename } = $text;
                $with_templates = 1;
                $text = $app->build_page( $tmpl, \%param );
            }
            $text =~ s/^sub/sub $handler/;
            $bootstraps->{ $basename } = {
                            class => 9,
                            text  => $text,
                            code  => $plugin_id . '::App::' . $handler,
            };
            if ( $job->requires_login ) {
                $bootstraps->{ $basename }->{ requires_login } = 1;
            }
            if ( $job->is_default ) {
                $bootstraps->{ $basename }->{ default } = 1;
            }
        } else {
            my $basename = $job->basename;
            $basename = _dirify( $basename );
            if (! $job->evalscript ) {
                my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'method.tmpl' );
                $param{ mtmljob_basename } = $basename;
                $param{ task } = 1;
                $plugin_templates->{ $basename } = $text;
                $with_templates = 1;
                $text = $app->build_page( $tmpl, \%param );
            }
            $tasks->{ $basename } = {
                # title => $job->title,
                title => $job->basename,
                interval => $job->interval,
                priority => $job->priority,
                detail => $job->detail,
                nextrun_on => $job->nextrun_on,
                code_ref => '_task_' . lc( $plugin_id ) . '_' . $job->basename,
                code => $text,
            };
        }
    }
    my @apis;
    my $api_codes = '';
    my $with_apis;
    if ( $endpoints ) {
        for my $key ( keys %$endpoints ) {
            my $api = $endpoints->{ $key };
            $api_codes .= "\n\n" if $api_codes;
            $api_codes .= $api->{ _handler };
            delete( $api->{ _handler } );
            $with_apis = 1;
            push ( @apis, $api );
        }
    }
    my $task_codes = '';
    my $task_settings_name;
    my $with_tasks;
    if ( $tasks ) {
        for my $key ( keys %$tasks ) {
            my $ref = $tasks->{ $key }->{ code_ref };
            my $code = $tasks->{ $key }->{ code };
            delete( $tasks->{ $key }->{ code } );
            # delete( $tasks->{ $key }->{ _title } );
            $code =~ s/^sub/sub $ref/;
            $code = _trim( $code );
            $task_codes .= $code . "\n\n";
            $with_tasks = 1;
        }
        if ( $with_tasks ) {
            $task_codes =~ s/\n$//s;
            my $task_settings = __dumper( $tasks );
            $task_settings =~ s/('code_ref' => )'(.*?)'/$1\\&$2/sg;
            $task_settings =~ s/\n{1,}$//s;
            $task_settings_name = '_task_' . lc( $plugin_id ) . '_settings';
            $task_settings = 'sub ' . $task_settings_name . " {\n    return " . $task_settings . "\n}\n\n";
            $task_codes = $task_settings . $task_codes;
            $task_codes =~ s/\n{1,}$//s;
        }
    }
    my $cb_codes;
    my $cb_counter = 0;
    for my $key ( keys %$callbacks ) {
        my $codes = $callbacks->{ $key }->{ code };
        my $name = lc( _dirify( $key ) );
        for my $code( @$codes ) {
            my $cb_name = '_cb_' . $name;
            $cb_name = __make_uniq_methname( $cb_codes, $cb_name );
            $cb_codes->{ $code } = $cb_name;
        }
    }
    my $meth_codes;
    for my $key ( keys %$methods ) {
        my $_app = $methods->{ $key };
        for my $_key( keys %$_app ) {
            my $name = lc( _dirify( $_key ) );
            $meth_codes->{ $key }->{ $_app->{ $_key }->{ code } } = '_app_' . $key . '_'  . $name;
        }
    }
    my $plugin_hash = {};
    my $plugin_methods = {};
    my $with_apps;
    for my $key ( keys %$methods ) {
        my $_app = $methods->{ $key };
        for my $_key( keys %$_app ) {
            my $name = lc( _dirify( $_key ) );
            if ( $_app->{ $_key }->{ requires_login } ) {
                $plugin_methods->{ $key }->{ methods }->{ $_key }->{ code } =
                    $plugin_id . '::' . $apps->{ $key } . '::' . $meth_codes->{ $key }->{ $_app->{ $_key }->{ code } };
                $plugin_methods->{ $key }->{ methods }->{ $_key }->{ requires_login } = $_app->{ $_key }->{ requires_login };
            } else {
                $plugin_methods->{ $key }->{ methods }->{ $_key } =
                    $plugin_id . '::' . $apps->{ $key } . '::' . $meth_codes->{ $key }->{ $_app->{ $_key }->{ code } };
            }
        }
        $with_apps = 1;
    }
    if ( $with_apps ) {
        $plugin_hash->{ applications } = $plugin_methods;
    }
    if ( $with_apis ) {
        $plugin_hash->{ applications }->{ data_api }->{ endpoints } = \@apis;
    }
    my $plugin_callbacks = {};
    my $with_cbs;
    for my $key ( keys %$callbacks ) {
        my $code_array = $callbacks->{ $key }->{ code };
        my $priority_array = $callbacks->{ $key }->{ priority };
        my $i = 0;
        my @callbacks;
        for my $c ( @$code_array ) {
            my $plugin_values = {};
            $plugin_values->{ handler } = $plugin_id . '::Callbacks::' .  $cb_codes->{ $c };
            $plugin_values->{ priority } = @$priority_array[ $i ];
            push ( @callbacks, $plugin_values );
            $i++;
        }
        $plugin_callbacks->{ $key } = \@callbacks;
        $with_cbs = 1;
    }
    if ( $with_cbs ) {
        $plugin_hash->{ callbacks } = $plugin_callbacks;
    }
    my $tempdir = $app->config( 'TempDir' );
    $tempdir = tempdir( DIR => $tempdir );
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    __mkpath( $fmgr, $tempdir );
    my $root_dir = File::Spec->catdir( $tempdir, 'mt' );
    my $out_zip = File::Spec->catfile( $tempdir, 'mt.zip' );
    my $plugin_dir = File::Spec->catdir( $root_dir, 'plugins', $plugin_id );
    __mkpath( $fmgr, $plugin_dir );
    my $php_dir = File::Spec->catdir( $plugin_dir, 'php' );
    __mkpath( $fmgr, $php_dir );
    my $lib_dir = File::Spec->catdir( $plugin_dir, 'lib', $plugin_id );
    __mkpath( $fmgr, $lib_dir );
    my $l10n_dir = File::Spec->catdir( $lib_dir, 'L10N' );
    __mkpath( $fmgr, $l10n_dir );
    my $app_dir = File::Spec->catdir( $plugin_dir, 'lib', 'MT', 'App' );
    __mkpath( $fmgr, $app_dir );
    my $plugin_tags = {};
    my @kinds = qw/ block function modifier /;
    my $plugin_handler = '';
    my $do;
    my $with_tags;
    if ( $tags ) {
        for my $kind ( @kinds ) {
            my $_tags = $tags->{ $kind };
            for my $key ( keys %$_tags ) {
                my $plugin_meth;
                if ( $kind ne 'modifier' ) {
                    $plugin_meth = '_hdlr_' . $key;
                } else {
                    $plugin_meth = '_filter_' . $key;
                }
                $plugin_meth = lc( $plugin_meth );
                $plugin_tags->{ $kind }->{ $key } = $plugin_id . '::Tags::' . $plugin_meth;
                $with_tags = 1;
                my $perl = $_tags->{ $key }->{ perl };
                $perl =~ s/^sub/sub ${plugin_meth}/;
                $plugin_handler .= "\n\n" if $plugin_handler;
                $plugin_handler .= $perl;
                my $php = $_tags->{ $key }->{ php };
                my $php_file;
                if ( $kind ne 'modifier' ) {
                    $php_file = File::Spec->catfile( $php_dir, $kind . '.mt' . lc( $key ) . '.php' );
                } else {
                    $php_file = File::Spec->catfile( $php_dir, $kind . '.' . lc( $key ) . '.php' );
                }
                $php =~ s/\r\n?/\n/g;
                $fmgr->put_data( "<?php\n" . $php, $php_file );
                $do = 1;
            }
        }
        if ( $with_tags ) {
            my $lib_file = File::Spec->catfile( $lib_dir, 'Tags.pm' );
            $param{ plugin_handler } = $plugin_handler;
            $param{ plugin_type } = 'tag';
            my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'module_pm.tmpl' );
            my $pm = $app->build_page( $tmpl, \%param );
            $pm =~ s/\r\n?/\n/g;
            $pm = _trim( $pm );
            if ( my $e = _eval( $pm ) ) {
                $error = 3;
                return $app->error( __trigger_error( $error, $e, $tempdir ) );
            }
            $fmgr->put_data( $pm, $lib_file );
            $do = 1;
        }
    }
    if ( $with_tags ) {
        $plugin_hash->{ tags } = $plugin_tags;
    }
    if ( $with_apis ) {
        my $lib_file = File::Spec->catfile( $lib_dir, 'DataAPI.pm' );
        my $module = quotemeta( 'MT::DataAPI::Endpoint::Common::' );
        $api_codes =~ s/$module//g;
        $module = quotemeta( 'MT::DataAPI::Endpoint::Resource::' );
        $api_codes =~ s/$module//g;
        $module = quotemeta( 'use MT::DataAPI::Endpoint::Common;' );
        $api_codes =~ s/\s{0,}$module\s//mg;
        $module = quotemeta( 'use MT::DataAPI::Resource;' );
        $api_codes =~ s/\s{0,}$module\s//mg;
        $param{ plugin_handler } = $api_codes;
        $param{ plugin_type } = 'endpoint';
        my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'module_pm.tmpl' );
        my $pm = $app->build_page( $tmpl, \%param );
        $pm =~ s/\r\n?/\n/g;
        $pm = _trim( $pm );
        if ( my $e = _eval( $pm ) ) {
            $error = 3;
            return $app->error( __trigger_error( $error, $e, $tempdir ) );
        }
        $fmgr->put_data( $pm, $lib_file );
        $do = 1;
    }
    my $with_bootstrap;
    my $bootstrap_handler = '';
    for my $key ( keys %$bootstraps ) {
        my $code = $bootstraps->{ $key }->{ text };
        $bootstrap_handler .= "\n\n" if $bootstrap_handler;
        $bootstrap_handler .= $code;
        delete( $bootstraps->{ $key }->{ text } );
        $with_bootstrap = 1;
    }
    my $app_registry = {};
    if ( $with_bootstrap ) {
        $plugin_hash->{ custom_handlers } = $bootstraps;
        my $default_handler = '';
        my $requires_login = '';
        for my $key ( keys %$bootstraps ) {
            my $d = $bootstraps->{ $key }->{ default };
            if ( $d ) {
                my $d_code = $bootstraps->{ $key }->{ code };
                my $d_m;
                if ( $d_code =~ /(^.*)::.*$/ ) {
                    $d_m = $1;
                }
                $default_handler = <<"CODE";
sub default {
    require $d_m;
    return $d_code( shift );
}
CODE
                my $r = $bootstraps->{ $key }->{ requires_login };
                if ( $r ) {
                    $requires_login = <<'CODE';
sub init_request {
    my $app = shift;
    $app->SUPER::init_request( @_ );
    if ( my $mode = $app->mode ) {
        if ( $mode eq 'default' ) {
            $app->{ requires_login } = 1;
        }
    }
    $app;
}
CODE
                }
            }
        }
        $param{ plugin_handler } = $bootstrap_handler;
        $param{ plugin_type } = 'bootstrap';
        my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'module_pm.tmpl' );
        my $pm = $app->build_page( $tmpl, \%param );
        $pm =~ s/\r\n?/\n/g;
        $pm = _trim( $pm );
        if ( my $e = _eval( $pm ) ) {
            $error = 3;
            return $app->error( __trigger_error( $error, $e, $tempdir ) );
        }
        my $lib_file = File::Spec->catfile( $lib_dir,  'App.pm' );
        $fmgr->put_data( $pm, $lib_file );
        my $app_file = File::Spec->catfile( $app_dir, $plugin_id . '.pm' );
        $tmpl = File::Spec->catfile( $component->path, 'lib', 'MT', 'App', 'Developer.pm' );
        $tmpl = $fmgr->get_data( $tmpl );
        $tmpl =~ s/Developer/$plugin_id/g;
        $tmpl =~ s/developer/$plugin_key/g;
        $tmpl =~ s/sub\sinit_request.*?##\n/$requires_login$default_handler/is;
        $fmgr->put_data( $tmpl, $app_file );
        # set config.yaml and settings.
        $app_registry->{ handler } = 'MT::App::' . $plugin_id;
        $app_registry->{ script } = 'sub { MT->config->' . $plugin_id . 'Script }';
        my @methods = qw( default start_recover recover new_pw signup do_signup do_register logout );
        for my $meth ( @methods ) {
            $app_registry->{ methods }->{ $meth } = 'MT::App::' . $plugin_id . '::' . $meth;
        }
        my @r_methods = qw( edit_profile save_profile withdraw );
        for my $meth ( @r_methods ) {
            $app_registry->{ methods }->{ $meth } = { 
                code => 'MT::App::' . $plugin_id . '::' . $meth,
                requires_login => 1 };
        }
        my $cfg_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'config_tmpl.tmpl' );
        my $tmpl_dir = File::Spec->catdir( $plugin_dir, 'tmpl' );
        __mkpath( $fmgr, $tmpl_dir );
        $param{ plugin_key } = $plugin_key;
        my $cfg_file = $fmgr->get_data( $cfg_tmpl );
        $cfg_file =~ s/developer/$plugin_key/g;
        $fmgr->put_data( $cfg_file, File::Spec->catfile( $tmpl_dir, 'config.tmpl' ) );
        my $cgi_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'mt_app_cgi.tmpl' );
        $pm = $app->build_page( $cgi_tmpl, \%param );
        $pm =~ s/\r\n?/\n/g;
        $pm = _trim( $pm );
        $lib_file = File::Spec->catfile( $plugin_dir,  'mt-' . $plugin_key . '.cgi' );
        $fmgr->put_data( $pm, $lib_file );
        $lib_file = File::Spec->catfile( $root_dir,  'mt-' . $plugin_key . '.cgi' );
        $fmgr->put_data( $pm, $lib_file );
        my $php_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'script_php.tmpl' );
        $pm = $app->build_page( $php_tmpl, \%param );
        $pm =~ s/\r\n?/\n/g;
        $pm = _trim( $pm );
        $lib_file = File::Spec->catfile( $php_dir,  'function.mt' . $plugin_key . 'script.php' );
        $fmgr->put_data( $pm, $lib_file );
        my @app_tmpls = qw( commenter_notify email_verification_email error login profile
                            recover signup_thanks signup );
        for my $t ( @app_tmpls ) {
            my $_tmpl = File::Spec->catfile( $component->path, 'tmpl', $t .'.tmpl' );
            my $_file = $fmgr->get_data( $_tmpl );
            $_file =~ s/Developer/$plugin_id/g;
            $_file =~ s/developer/$plugin_key/g;
            $fmgr->put_data( $_file, File::Spec->catfile( $tmpl_dir, $t. '.tmpl' ) );
        }
        $do = 1;
    }
    if ( $cb_codes ) {
        my $plugin_handler = '';
        for my $_code ( keys %$cb_codes ) {
            my $h = $cb_codes->{ $_code };
            $_code =~ s/^sub/sub ${h}/;
            $plugin_handler .= "\n\n" if $plugin_handler;
            $plugin_handler .= $_code;
        }
        $param{ plugin_handler } = $plugin_handler;
        $param{ plugin_type } = 'callback';
        my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'module_pm.tmpl' );
        my $pm = $app->build_page( $tmpl, \%param );
        $pm =~ s/\r\n?/\n/g;
        $pm = _trim( $pm );
        if ( my $e = _eval( $pm ) ) {
            $error = 3;
            return $app->error( __trigger_error( $error, $e, $tempdir ) );
        }
        my $lib_file = File::Spec->catfile( $lib_dir,  'Callbacks.pm' );
        $fmgr->put_data( $pm, $lib_file );
        $do = 1;
    }
    if ( $meth_codes ) {
        for my $key ( keys %$meth_codes ) {
            my $plugin_handler = '';
            my $module_id = app_ref2pkg( id2app_ref( $key ) );
            my $lib_file = File::Spec->catfile( $lib_dir, $module_id . '.pm' );
            my $code_arr = $meth_codes->{ $key };
            for my $_code ( keys %$code_arr ) {
                my $h = $code_arr->{ $_code };
                $_code =~ s/^sub/sub ${h}/;
                $plugin_handler .= "\n\n" if $plugin_handler;
                $plugin_handler .= $_code;
            }
            $param{ plugin_handler } = $plugin_handler;
            $param{ plugin_type } = 'method';
            $param{ module_id } = $module_id;
            my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'module_pm.tmpl' );
            my $pm = $app->build_page( $tmpl, \%param );
            $pm =~ s/\r\n?/\n/g;
            $pm = _trim( $pm );
            if ( my $e = _eval( $pm ) ) {
                $error = 3;
                return $app->error( __trigger_error( $error, $e, $tempdir ) );
            }
            $fmgr->put_data( $pm, $lib_file );
            $do = 1;
        }
    }
    if ( $with_tasks ) {
        my $lib_file = File::Spec->catfile( $lib_dir, 'Tools.pm' );
        $param{ plugin_handler } = $task_codes;
        $param{ plugin_type } = 'task';
        $param{ module_id } = 'Tools';
        $param{ task_settings_name } = $task_settings_name;
        my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'module_pm.tmpl' );
        my $pm = $app->build_page( $tmpl, \%param );
        $pm =~ s/\r\n?/\n/g;
        $pm = _trim( $pm );
        if ( my $e = _eval( $pm ) ) {
            $error = 3;
            return $app->error( __trigger_error( $error, $e, $tempdir ) );
        }
        $fmgr->put_data( $pm, $lib_file );
        $do = 1;
        my $task_label = $app->param( 'plugin_task_label' ) || $plugin_id;
        $plugin_hash->{ tasks } = { $plugin_id . 'ScheduledTasks' => {
                                                label => $task_label,
                                                frequency => 180,
                                                code => $plugin_id . '::Tools::_do_task',
                                                priority => 5,
                                            } };
    }
    if ( $with_templates ) {
        my $tmpl_dir = File::Spec->catdir( $plugin_dir, 'tmpl', 'handlers' );
        __mkpath( $fmgr, $tmpl_dir );
        for my $key ( keys %$plugin_templates ) {
            my $tmpl_path = File::Spec->catfile( $tmpl_dir, $key . '.tmpl' );
            $fmgr->put_data( $plugin_templates->{ $key }, $tmpl_path );
        }
    }
    if ( $do ) {
        if ( @yamls ) {
            for my $job( @yamls ) {
                my $cfg = $job->text;
                $cfg = MT::Util::YAML::Load( $cfg );
                my @uniqkeys = qw( id name key version author_name
                    author_link description version l10n_class );
                for my $key ( @uniqkeys ) {
                    delete( $cfg->{ $key } );
                }
                $plugin_hash = merge( $plugin_hash, $cfg );
            }
        }
        if ( $with_bootstrap ) {
            $plugin_hash->{ applications }->{ $plugin_key } = $app_registry;
            $plugin_hash->{ settings }->{ $plugin_key . '_signup_notify_to' }->{ default } = '';
            $plugin_hash->{ system_config_template } = 'config.tmpl';
            $plugin_hash->{ config_settings }->{ $plugin_id .
                'Script' } = { default => 'mt-' . $plugin_key . '.cgi',
                               updatable => 1 };
            $plugin_hash->{ tags }->{ function }->{ $plugin_id . 'Script' } = 'sub { MT->config->' . $plugin_id . 'Script }';
            $plugin_hash->{ callbacks }->{ 'MT::App::' . $plugin_id . '::template_source.login' }
                = { handler => 'MT::App::' . $plugin_id . '::_login_tmpl', priority => 1 };
            $plugin_hash->{ callbacks }->{ 'MT::App::' . $plugin_id . '::template_source.error' }
                = { handler => 'MT::App::' . $plugin_id . '::_error_tmpl', priority => 1 };
        }
        my $yaml = MT::Util::YAML::Dump( $plugin_hash );
        $yaml =~ s/^\-{1,}//;
        my $meta = "name: ${orig_name}\n" . 
                "id:   ${plugin_id}";
        if ( my $version = $app->param( 'plugin_version' ) ) {
            $version = __sanitize_short( $version );
            $meta .= "\nversion: ${version}";
        }
        my ( $author_name, $author_link, $description );
        if ( $app->param( 'plugin_author_name' ) ) {
            $author_name = $app->param( 'plugin_author_name' );
        } else {
            $author_name = $component->get_config_value( 'developer_plugin_author_name' );
        }
        if ( $author_name ) {
            $meta .= "\nauthor_name: ${author_name}";
        }
        if ( $app->param( 'plugin_author_link' ) ) {
            $author_link = $app->param( 'plugin_author_link' );
        } else {
            $author_link = $component->get_config_value( 'developer_plugin_author_link' );
        }
        if ( $author_link ) {
            $meta .= "\nauthor_link: ${author_link}";
        }
        if ( $app->param( 'plugin_description' ) ) {
            $description = $app->param( 'plugin_description' );
            $description = __sanitize_long( $description );
            $description = '<__trans phrase="' . $description . '">';
            $meta .= "\ndescription: ${description}";
        } else {
            # $description = "${orig_name}'s description.";
        }
        my $lib_file = File::Spec->catfile( $lib_dir,  'L10N.pm' );
        my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'L10N_pm.tmpl' );
        my $pm = $app->build_page( $tmpl, \%param );
        $pm =~ s/\r\n?/\n/g;
        $pm = _trim( $pm );
        if ( my $e = _eval( $pm ) ) {
            $error = 3;
            return $app->error( __trigger_error( $error, $e, $tempdir ) );
        }
        $fmgr->put_data( $pm, $lib_file );
        $meta .= "\nl10n_class: ${plugin_id}::L10N";
        $yaml = $meta . $yaml;
        my $tiny = MT::Util::YAML::Load( $yaml );
        if (! $tiny->{ name } ) {
            $error = 4;
            return $app->error( __trigger_error( $error, undef, $tempdir ) );
        }
        my @languages = qw( en_us );
        if ( $app->user->preferred_language ne 'en_us' ) {
            push( @languages, $app->user->preferred_language );
        }
        for my $language ( @languages ) {
            my @_params = qw/ plugin_description plugin_task_label /;
            my $lexicon;
            # my $lexicon_table;
            if ( $language ne 'en_us' ) {
                for my $p ( @_params ) {
                    if ( my $en_us = $app->param( $p ) ) {
                        if ( my $my_lang = $app->param( $p . '_lang' ) ) {
                            $lexicon->{ $en_us } = $my_lang;
                            # $lexicon_table->{ $en_us } = $my_lang;
                        }
                    }
                }
                if ( $with_bootstrap ) {
                    $lexicon->{ 'Sign Up Notify Send To' } =
                        $component->translate( 'Sign Up Notify Send To' );
                    $lexicon->{ 'Thanks for the confirmation. Please sign in.' } =
                        $component->translate( 'Thanks for the confirmation. Please sign in.' );
                }
            }
            if ( $lexicon ) {
                $lexicon = __dumper( $lexicon );
                $lexicon =~ s/^{//;
                $lexicon =~ s/}$//;
                $lexicon =~ s/\n$//;
                $lexicon =~ s/\n\s{12}([^\s]{1})/\n    $1/g;
                $param{ lexicon } = $lexicon;
            }
            $param{ my_language_id } = $language;
            my $l10n_file = File::Spec->catfile( $l10n_dir,  $language . '.pm' );
            my $pm = $app->build_page( $tmpl, \%param );
            $pm =~ s/\r\n?/\n/g;
            $pm = _trim( $pm );
            if ( my $e = _eval( $pm ) ) {
                $error = 3;
                return $app->error( __trigger_error( $error, $e, $tempdir ) );
            }
            $fmgr->put_data( $pm, $l10n_file );
        }
        my $yaml_file = File::Spec->catfile( $plugin_dir, 'config.yaml' );
        $yaml = __indent( $yaml );
        $fmgr->put_data( $yaml, $yaml_file );
        return __download_zip( $app, $tempdir, $out_zip );
        # my $res = make_zip_archive( $tempdir, $out_zip );
        # $app->{ no_print_body } = 1;
        # my $basename = File::Basename::basename( $out_zip );
        # $app->set_header( 'Content-Disposition' => "attachment; filename=$basename" );
        # $app->set_header( 'Pragma' => '' );
        # $app->send_http_header( 'application/zip' );
        # if ( open( my $fh, '<', $out_zip ) ) {
        #     binmode $fh;
        #     my $data;
        #     while ( read $fh, my ( $chunk ), 8192 ) {
        #         $data .= $chunk;
        #         $app->print( $chunk );
        #     }
        #     close $fh;
        # }
    }
    File::Path::rmtree( [ $tempdir ] );
    if (! $do ) {
        $app->add_return_arg( not_exported => 1 );
        return $app->call_return;
    }
}

sub __make_uniq_methname {
    my ( $methods, $name ) = @_;
    $name = _dirify( $name );
    my @names;
    for my $key( keys %$methods ) {
        push ( @names, $methods->{ $key } );
    }
    if ( grep( /^$name$/, @names ) ) {
        my $counter = 0;
        my $meth_name = $name;
        while ( 1 ) {
            $counter++;
            my $meth_name = $name;
            $meth_name .= '_' . $counter;
            if (! grep( /^$meth_name$/, @names ) ) {
                $name = $meth_name;
                last;
            }
        }
    }
    return $name;
}

sub __mkpath {
    my $fmgr = shift;
    my $dir;
    if ( ( ref $fmgr ) ne 'MT::FileMgr::Local' ) {
        $dir = $fmgr;
        require MT::FileMgr;
        $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    }
    $dir = shift;
    $dir =~ s!/$!! unless $dir eq '/';
    if (! $fmgr->exists( $dir ) ) {
        $fmgr->mkpath( $dir ) or return undef;
    }
    $dir;
}

sub _export_alttemplates {
    my $app = shift;
    my $author = $app->user;
    if ( $author->is_superuser ) {
        $app->validate_magic
            or return $app->errtrans( 'Invalid request.' );
    } else {
        $app->return_to_dashboard( permission => 1 );
        return;
    }
    my $component = MT->component( 'Developer' );
    my @ids = $app->param( 'id' );
    my @alt_templates = MT->model( 'alttemplate' )->load( { id => \@ids } );
    if (! scalar @alt_templates ) {
        $app->add_return_arg( not_exported => 1 );
        return $app->call_return;
    }
    my $tempdir = $app->config( 'TempDir' );
    $tempdir = tempdir( DIR => $tempdir );
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    __mkpath( $fmgr, $tempdir );
    my $root_dir = File::Spec->catdir( $tempdir, 'alt-tmpl' );
    my $out_zip = File::Spec->catfile( $tempdir, 'alt-tmpl.zip' );
    for my $tmpl ( @alt_templates ) {
        my $out_path = $root_dir;
        if ( my $app_ref = $tmpl->app_ref ) {
            my $dir = app_ref2id( $app_ref );
            $dir = File::Spec->catdir( $root_dir, $dir );
            $out_path = __mkpath( $fmgr, $dir );
        }
        my $basename = $tmpl->template;
        $basename =~ s/\.tmpl$//;
        $out_path = File::Spec->catfile( $out_path, $tmpl->template . '.tmpl' );
        $fmgr->put_data( $tmpl->text, $out_path );
    }
    return __download_zip( $app, $tempdir, $out_zip );
    # my $res = make_zip_archive( $tempdir, $out_zip );
    # $app->{ no_print_body } = 1;
    # my $basename = File::Basename::basename( $out_zip );
    # $app->set_header( 'Content-Disposition' => "attachment; filename=$basename" );
    # $app->set_header( 'Pragma' => '' );
    # $app->send_http_header( 'application/zip' );
    # if ( open( my $fh, '<', $out_zip ) ) {
    #     binmode $fh;
    #     my $data;
    #     while ( read $fh, my ( $chunk ), 8192 ) {
    #         $data .= $chunk;
    #         $app->print( $chunk );
    #     }
    #     close $fh;
    # }
    # File::Path::rmtree( [ $tempdir ] );
    # $app->add_return_arg( exported => scalar @alt_templates );
    # return $app->call_return;
}

sub __trigger_error {
    my ( $error, $msg, $tempdir ) = @_;
    my $component = MT->component( 'Developer' );
    File::Path::rmtree( [ $tempdir ] ) if $tempdir;
    if ( $msg ) {
        $msg = encode_html( $msg );
    }
    if ( $error == 1 ) {
        return $component->translate( 'Invalid Plugin ID\'[_1]\'.', $msg );
    } elsif ( $error == 2 ) {
        return $component->translate( 'Plugin \'[_1]\' already exist.', $msg );
    } elsif ( $error == 3 ) {
        return $component->translate( 'Parser error (\'[_1]\'.)', $msg );
    } elsif ( $error == 4 ) {
        return $component->translate( 'Parser error in \'config.yaml\'.' );
    } elsif ( $error == 5 ) {
        return $component->translate( 'Model \'[_1]\' already exist.', $msg );
    }
    return $error;
}

sub __indent {
    my $yaml = shift;
    my $max = 12;
    for ( 0 .. $max ) {
        my $space = $max - $_;
        $space = $space * 2;
        $yaml =~ s/\n(\s{$space})([^\s]{1})/\n$1$1$2/g;
    }
    return $yaml . "\n";
}

sub __dumper {
    my ( $hash, $not_quote ) = @_;
    my $res = "{\n";
    for my $key ( keys %$hash ) {
        my $value = $hash->{ $key };
        if ( ( ref $value ) eq 'HASH' ) {
            $value = __dumper( $value, 1 );
            $res .= "        '${key}' => ${value},\n"
        } else {
            $value =~ s/'/\\'/g;
            $key =~ s/'/\\'/g;
            $res .= "            '${key}' => '${value}',\n"
        }
    }
    if ( $not_quote ) {
        $res .= '    ';
    }
    $res .= "    }";
    return $res;
}

sub __sanitize_column {
    my $text = shift;
    $text =~ s/[^a-zA-Z0-9_]//g;
    return lc( $text );
}

sub __sanitize_short {
    my $text = shift;
    $text =~ s/[\r\n\t\@#%:\$'\\]+//g;
    $text = encode_html( $text );
    return $text;
}

sub __sanitize_long {
    my $text = shift;
    $text =~ s/[\r\n\t#\\]+//g;
    $text =~ s/([\@#%\$])/\\$1/g;
    $text = encode_html( $text );
    return $text;
}

sub _preview_mtmljob {
    my $app = shift;
    my $mt = MT->instance;
    my $allow_perl = $app->config( 'DoCommandInPreview' );
    my $component = MT->component( 'Developer' );
    my $allow_command = $app->config( 'DoCommandInPreview' );
    my $author = $app->user;
    if ( $author->is_superuser ) {
        $app->validate_magic
            or return $app->errtrans( 'Invalid request.' );
    } else {
        $app->return_to_dashboard( permission => 1 );
        return;
    }
    my $job = MT->model( 'mtmljob' )->new;
    $job->title( $app->param( 'title' ) );
    $job->id( $app->param( 'id' ) );
    my @params = $app->param;
    for my $name ( @params ) {
        next unless $name;
        if ( $name =~ /^customfield_(.*$)/ ) {
            my $basename = 'field.'. $1;
            my $value = $app->param( $name );
            if ( $job->has_column( $basename ) ) {
                $job->$basename( $value );
            }
        }
    }
    my $out = $app->param( 'text' );
    my $interval = $app->param( 'interval' ) || 0;
    require MT::Template::Context;
    require MT::Builder;
    my $ctx = MT::Template::Context->new;
    if ( $interval == 9 ) {
        if ( my $user = $app->user ) {
            $ctx->{ __stash }{ vars }{ magic_token } = $app->current_magic();
            $ctx->stash( 'author', $user );
        }
        if ( my $blog = $app->blog ) {
            $ctx->stash( 'blog', $blog );
            $ctx->stash( 'blog_id', $blog->id );
        }
    }
    $ctx->stash( 'mtmljob', $job );
    my @data;
    $app->run_callbacks( 'cms_pre_preview', $app, $job, \@data );
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'preview_mtmljob.tmpl' );
    my %param;
    $param{ handler_name } = $app->param( 'title' );
    if ( $interval == 12 ) {
        my $cfg = $app->param( 'text' );
        my $error = compile_test( $cfg, 'yaml' );
        if ( $error ne 'OK' ) {
            return $app->error( $component->translate(
            'An error occurred while trying to Load config.yaml \'[_1]\'',
                encode_html( $error ) ) );
        } else {
            my $tempdir = $app->config( 'TempDir' );
            $tempdir = tempdir( DIR => $tempdir );
            require MT::FileMgr;
            my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
            __mkpath( $fmgr, $tempdir );
            my $plugin_dir = File::Spec->catdir( $tempdir, 'test' );
            __mkpath( $fmgr, $plugin_dir );
            my $config_yaml = File::Spec->catfile( $plugin_dir, 'config.yaml' );
            $fmgr->put_data( $cfg, $config_yaml );
            MT->_init_plugins_core( {}, 1, [ $tempdir ] );
            File::Path::rmtree( [ $tempdir ] );
            $param{ preview_result } = $component->translate( 'Load config.yaml OK.' );
            $mt->reboot;
            return $app->build_page( $tmpl, \%param );
            # return $component->translate( 'Load config.yaml OK.' );
        }
    }
    if ( $app->param( 'evalscript' ) && $allow_perl && $allow_command ) {
        # <mt:if name="request.__mode" eq="preview_mtmljob">~</mt:if>
        my $comp = src2sub( $out, 'test' );
        $out = src2sub( $out );
        my $error = compile_test( $comp );
        if ( $error ne 'OK' ) {
            return $app->error( $component->translate(
                'An error occurred while trying to require \'[_1]\'', encode_html( $error ) ) );
        }
        my $freq = MT->handler_to_coderef( $out );
        if ( ( $interval == 9 ) || ( $interval == 10 ) || ( $interval == 11 ) ) {
            if ( $interval == 11 ) {
                require MT::DataAPI::Endpoint::Common;
                require MT::DataAPI::Resource;
                # $freq = $freq->( $app );
                my $response = $freq->( $app );
                if ( ref $response ) {
                    my $format = 'json';
                    my $fields = $app->param( 'fields' ) || '';
                    require MT::App::DataAPI;
                    require MT::DataAPI::Format::JSON;
                    $response = MT::App::DataAPI::object_to_resource( MT::App::DataAPI->new, $response,
                        $fields ? [ split ',', $fields ] : undef );
                    $response = MT::DataAPI::Format::JSON::serialize( $response );
                }
                $param{ preview_result } = $response;
                $mt->reboot;
                return $app->build_page( $tmpl, \%param );
                # return '<pre><code>' . encode_html( Dumper $freq );
            }
            $freq = $freq->( $app );
            $param{ preview_result } = $freq;
            $mt->reboot;
            return $app->build_page( $tmpl, \%param );
            # return encode_html( $freq );
        } elsif ( $interval == 7 ) {
            require MT::Callback;
            my $cb = MT::Callback->new;
            $cb->{ plugin } = $component;
            if ( my $detail = $app->param( 'detail' ) ) {
                my @cbs = split( /,/, $detail );
                my $meth = $cbs[ 0 ];
                $cb->{ method } = 'preview_customhandler';
                if ( $meth =~ m/cms_/ ) {
                    # TODO:: Build Parameter
                    $param{ preview_result } = $freq->( $cb, $app, $job );
                    $mt->reboot;
                    return $app->build_page( $tmpl, \%param );
                }
            } else {
                $cb->{ method } = 'preview_customhandler';
            }
            my $args = {};
            $param{ preview_result } = $freq->( $cb, $args );
            $mt->reboot;
            return $app->build_page( $tmpl, \%param );
        } else {
            if ( $interval != 8 ) {
                $freq = $freq->( $app );
                $param{ preview_result } = $freq;
                $mt->reboot;
                return $app->build_page( $tmpl, \%param );
            }
        }
    }
    if ( $interval == 8 ) {
        $out = $app->param( 'test_mtml' );
    }
    $out = $app->translate_templatized( $out );
    if ( ( $interval != 11 ) && ( $interval != 8 ) ) {
        if ( my $app_ref = $app->param( 'app_ref' ) ) {
            # if ( $app_ref eq 'MT::App::CMS' ) {
                my $tmpl = MT->model( 'template' )->new;
                $tmpl->text( $out );
                if ( $app_ref eq 'MT::App::CMS' ) {
                    $app->set_default_tmpl_params( $tmpl );
                }
                my $params = $tmpl->param;
                if ( my $basename = $app->param( 'basename' ) ) {
                    MT->run_callbacks( $app_ref . '::template_cource.' . $basename, $app, \$out );
                    $params = $tmpl->param;
                    $tmpl->text( $out );
                    MT->run_callbacks( $app_ref . '::template_param.' . $basename, $app, $params, $tmpl );
                    my $output = $app->build_page( $tmpl, $params );
                    MT->run_callbacks( $app_ref . '::template_output.' . $basename, $app, \$output, $params, $tmpl );
                    return $output;
                }
                return $app->build_page( $tmpl, $params );
            # }
        }
    }
    my $build = MT::Builder->new;
    my $tokens = $build->compile( $ctx, $out )
        or return( encode_html( $component->translate(
            'Parse error: [_1]', $build->errstr ) ) );
    defined( my $html = $build->build( $ctx, $tokens ) )
        or return( encode_html( $component->translate(
            'Build error: [_1]', $build->errstr ) ) );
    if ( $interval == 8 ) {
        $mt->reboot;
        return $html;
    }
    if ( $interval == 11 ) {
        $html =~ s/\r|\n|\t//g;
        eval {
            require MT::DataAPI::Format::JSON;
            $html = MT::DataAPI::Format::JSON::unserialize( $html );
            $html = MT::DataAPI::Format::JSON::serialize( $html );
        };
    }
    $param{ preview_result } = $html;
    # $mt->reboot;
    return $app->build_page( $tmpl, \%param );
}

sub _cms_save_filter_alttemplate {
    my ( $cb, $app ) = @_;
    my $component = MT->component( 'Developer' );
    my $name = $app->param( 'name' );
    if (! $name ) {
        return $cb->error( $component->translate( 'An Alt Template\'s name is required.' ) );
    }
    my $id = $app->param( 'id' );
    if (! $id ) {
        $id = 0;
    }
    my $template = $app->param( 'template' );
    if (! $template ) {
        return $cb->error( $component->translate( 'An Alt Template\'s template name is required.' ) );
    } else {
        if ( $template =~ /\.tmpl$/ ) {
            $template =~ s/\.tmpl$//;
            $app->param( 'template', $template );
        }
        my $app_ref = $app->param( 'app_ref' ) || '';
        my $alttemplate = MT->model( 'alttemplate' )->load( { app_ref => $app_ref,
                                                              template => $template } );
        if ( defined $alttemplate ) {
            if ( $id != $alttemplate->id ) {
                return $cb->error( $component->translate(
                    'An Alt Template for the same template already exists.' ) );
            }
        }
    }
    my $alttemplate = MT->model( 'alttemplate' )->load( { name => $name, id => { not => $id } } );
    if ( defined $alttemplate ) {
        return $cb->error( $component->translate( 'An Alt Template with the same name already exists.' ) );
    }
    eval {
        require CustomFields::App::CMS;
        return CustomFields::App::CMS::CMSSaveFilter_customfield_objs( 'alttemplate', @_ );
    };
    return 1;
}

sub _cms_save_filter_mtmljob {
    my ( $cb, $app ) = @_;
    my $component = MT->component( 'Developer' );
    my $title = $app->param( 'title' );
    if (! $title ) {
        return $cb->error( $component->translate( 'A Custom Handler\'s title is required.' ) );
    }
    my $id = $app->param( 'id' );
    if (! $id ) {
        $id = 0;
    }
    my $mtmljob = MT->model( 'mtmljob' )->load( { title => $title, id => { not => $id } } );
    if ( defined $mtmljob ) {
        return $cb->error( $component->translate( 'A Custom Handler with the same title already exists.' ) );
    }
    my $interval = $app->param( 'interval' );
    if ( $interval ) {
        my $detail = $app->param( 'detail' );
        if ( ( ( $interval > 4 ) && ( $interval < 9 ) ) || ( $interval == 10 ) || ( $interval == 11 ) ) {
            if (! $detail ) {
                return $cb->error( $component->translate( 'A Custom Handler\'s detail is required.' ) );
            }
        }
        if ( $interval == 10 ) {
            my @meths = split( /,/, $detail );
            if ( my $app_ref = $app->param( 'app_ref' ) ) {
                my $_apps = MT::Component->registry( 'applications' );
                if ( ( ref( $_apps ) ) eq 'ARRAY' ) {
                    $_apps = @$_apps[ 0 ];
                }
                my $app_id = app_ref2id( $app_ref, $_apps );
                my $methods = $_apps->{ $app_id }->{ methods };
                for my $meth ( @meths ) {
                    if ( $methods->{ $meth } ) {
                        return $cb->error( $component->translate( 'The Method with the same name already exists.' ) );
                    }
                }
            }
        }
        if ( $interval == 12 ) {
            my $cfg = $app->param( 'text' );
            my $error = compile_test( $cfg, 'yaml' );
            if ( $error ne 'OK' ) {
                return $cb->error( $component->translate( 'An error occurred while trying to Load config.yaml \'[_1]\'', encode_html( $error ) ) );
            }
        }
    }
    my $basename = $app->param( 'basename' );
    if (! $basename ) {
        $basename = lc(_dirify( $title ) );
        $basename = 'custom_handler' if (! $basename );
        $basename = MT::Util::_get_basename( MT->model( 'mtmljob' ), lc(_dirify( $basename ) ) );
    } else {
        $basename = lc( _dirify( $basename ) );
    }
    $mtmljob = MT->model( 'mtmljob' )->load( { basename => $basename, id => { not => $id } } );
    if ( defined $mtmljob ) {
        $basename = MT::Util::_get_basename( MT->model( 'mtmljob' ), lc(_dirify( $basename ) ) );
    }
    $app->param( 'basename', $basename );
    if ( $app->param( 'evalscript' ) ) {
        my $code = $app->param( 'text' );
        $code = src2sub( $code, 'test' );
        my $error = compile_test( $code );
        if ( $error ne 'OK' ) {
            return $cb->error( $component->translate( 'An error occurred while trying to require \'[_1]\'',
                    encode_html( $error ) ) );
        }
        if ( $interval == 8 ) {
            if ( my $php_path = $component->get_config_value( 'developer_php_path' ) ) {
                my $text_php = $app->param( 'text_php' );
                my $error = compile_test( $text_php, 'php' );
                if ( $error ne 'OK' ) {
                    return $cb->error( $component->translate( 'An error occurred while trying to require \'[_1]\'',
                            encode_html( $error ) ) );
                }
            }
        }
    }
    eval {
        require CustomFields::App::CMS;
        return CustomFields::App::CMS::CMSSaveFilter_customfield_objs( 'mtmljob', @_ );
    };
    return 1;
}

sub _change_status_alttemplate {
    my $app = shift;
    return _change_status_jobs( $app, 'alttemplate' );
}

sub _change_status_jobs {
    my $app = shift;
    my $class = shift || 'mtmljob';
    my $author = $app->user;
    if ( $author->is_superuser ) {
        $app->validate_magic
            or return $app->errtrans( 'Invalid request.' );
    } else {
        return $app->return_to_dashboard( permission => 1 );
    }
    my $component = MT->component( 'Developer' );
    my $action_name = $app->param( 'action_name' );
    my $status;
    my ( $status_from, $status_to );
    if ( $action_name =~ m/enable/ ) {
        $status = 2;
        $status_to = $component->translate( 'Enabled' );
        $status_from = $component->translate( 'Disabled' );
    } else {
        $status = 1;
        $status_to = $component->translate( 'Disabled' );
        $status_from = $component->translate( 'Enabled' );
    }
    if (! $status ) {
        return $app->errtrans( 'Invalid request.' );
    }
    my @ids = $app->param( 'id' );
    if (! scalar @ids ) {
        return $app->errtrans( 'Invalid request.' );
    }
    my @jobs = MT->model( $class )->load( { id => \@ids } );
    my $do = 0;
    for my $job( @jobs ) {
        if ( $job->status != $status ) {
            $job->status( $status );
            $job->save or die $job->errstr;
            $do++;
        }
    }
    if ( $do ) {
        $app->log( {
            message => $component->translate( '[_1] [_2] status changed from [_3] to [_4] by \'[_5]\'',
                 $do, MT->model( $class )->class_label, $status_from, $status_to, $app->user->name ),
            author_id => $app->user->id,
            class =>  MT->model( $class )->class_label_raw,
            level => MT::Log::INFO(),
        } );
    }
    return $app->call_return;
}

sub _cb_edit_template {
    my ( $cb, $app, $param, $tmpl ) = @_;
    my $component = MT->component( 'Developer' );
    if ( $app->blog ) {
        return;
    }
    my $obj;
    if ( my $id = $app->param( 'id' ) ) {
        $obj = MT->model( 'template' )->load( $id );
    }
    $param->{ use_revision } = 1;
    my $rn = $app->param( 'r' ) || 0;
    if ( $obj->current_revision > 0 || $rn != $obj->current_revision ) {
        my $rev = $obj->load_revision( { rev_number => $rn } );
        if ( $rev && @$rev ) {
            $obj = $rev->[ 0 ];
            my $values = $obj->get_values;
            $param->{ $_ } = $values->{ $_ } foreach keys %$values;
            $param->{ loaded_revision } = 1;
        }
        $param->{ rev_number } = $rn;
        $param->{ rev_date }   = format_ts( "%Y-%m-%d %H:%M:%S",
            $obj->modified_on, undef,
            $app->user ? $app->user->preferred_language : undef );
        $param->{ no_snapshot } = 1 if $app->param( 'no_snapshot' );
    }
}

sub _cms_pre_save_template {
    my ( $cb, $app, $obj, $original ) = @_;
    if ( $app->blog ) {
        return 1;
    }
    if (! $obj->id ) {
        return 1;
    }
    $obj->handle_max_revisions( MT->config( 'SystemTemplateMaxRevisions' ) );
    return 1;
}

sub _cms_pre_save_customschema {
    my ( $cb, $app, $obj, $original ) = @_;
    my @tl = offset_time_list( time, undef );
    my $ts = sprintf '%04d%02d%02d%02d%02d%02d', $tl[ 5 ] + 1900, $tl[ 4 ] + 1, @tl[ 3, 2, 1, 0 ];
    $obj->modified_on( $ts );
    $obj->modified_by( $app->user->id );
    return 1;
}

sub _cms_pre_save_alttemplate {
    my ( $cb, $app, $obj, $original ) = @_;
    if ( $app->blog ) {
        return 1;
    }
    if (! $obj->id ) {
        return 1;
    }
    $obj->handle_max_revisions( MT->config( 'AltTemplateMaxRevisions' ) );
    return 1;
}

sub _edit_alttemplate_param {
    my ( $cb, $app, $param, $tmpl ) = @_;
    if ( $app->user->is_superuser ) {
        # continue
    } else {
        $app->return_to_dashboard( permission => 1 );
        return;
    }
    if ( $app->blog ) {
        $app->return_to_dashboard();
        return;
    }
    my $component = MT->component( 'Developer' );
    my $obj;
    if ( my $id = $app->param( 'id' ) ) {
        $obj = MT->model( 'alttemplate' )->load( $id );
    }
    if ( $obj ) {
        my $rn = $app->param( 'r' );
        if ( defined( $rn ) && $rn != $obj->current_revision ) {
            my $rev = $obj->load_revision( { rev_number => $rn } );
            if ( $rev && @$rev ) {
                $obj = $rev->[ 0 ];
                my $values = $obj->get_values;
                $param->{ $_ } = $values->{ $_ } foreach keys %$values;
                $param->{ loaded_revision } = 1;
            }
            $param->{ rev_number } = $rn;
        }
        $param->{ rev_date } = format_ts( '%Y-%m-%d %H:%M:%S',
        $obj->modified_on, undef,
        $app->user ? $app->user->preferred_language : undef );
        my $error = $obj->compile;
        if ( $obj->{ errors } && @{ $obj->{ errors } } ) {
            $param->{error} = $app->translate(
                "One or more errors were found in this template." );
            $param->{ error } .= "<ul>\n";
            foreach my $err ( @{ $obj->{errors} } ) {
                $param->{ error }
                    .= "<li>"
                    . encode_html( $err->{ message } )
                    . "</li>\n";
            }
            $param->{ error } .= "</ul>\n";
        }
    }
    if (! $param->{ id } ) {
        $param->{ status } = $component->get_config_value( 'developer_default_alttemplate_status' );
    }
    # Populate structure for tag documentation
    my $all_tags = MT::Component->registry( 'tags' );
    my $tag_docs = {};
    foreach my $tag_set ( @$all_tags ) {
        my $url = $tag_set->{ help_url };
        $url = $url->() if ref( $url ) eq 'CODE';
        # hey, at least give them a google search
        $url ||= 'http://www.google.com/search?q=mt%t';
        my $tag_list = '';
        foreach my $type ( qw( block function ) ) {
            my $tags = $tag_set->{ $type } or next;
            $tag_list
                .= ( $tag_list eq '' ? '' : ',' ) . join( ",", keys( %$tags ) );
        }
        $tag_list =~ s/(^|,)plugin(,|$)/,/;
        if ( exists $tag_docs->{ $url } ) {
            $tag_docs->{ $url } .= ',' . $tag_list;
        } else {
            $tag_docs->{ $url } = $tag_list;
        }
    }
    my $all_apps = MT->registry( 'applications' );
    my @apps_loop;
    push ( @apps_loop, { label => MT->translate( 'All' ), app_name => '' } );
    push ( @apps_loop, { label => 'MT::App::CMS', app_name => 'MT::App::CMS' } );
    for my $mtapp( keys %$all_apps ) {
        if ( my $handler = $all_apps->{ $mtapp }->{ handler } ) {
            if ( $handler ne 'MT::App::CMS' ) {
                if ( $handler ne 'MT::App::Upgrader' ) {
                    push ( @apps_loop, { label => $handler, app_name => $handler } );
                }
            }
        }
    }
    $param->{ apps_loop } = \@apps_loop;
    $param->{ tag_docs } = $tag_docs;
    $param->{ screen_group } = 'design';
    my $perms = $app->user->permissions;
    my $template_prefs = $perms->template_prefs if $perms;
    $template_prefs =~ s/syntax://;
    $template_prefs =~ s/,.*$//;
    $param->{ disp_prefs_syntax } = $template_prefs;
    eval {
        require CustomFields::App::CMS;
        CustomFields::App::CMS::add_app_fields( $cb, $app, $param, $tmpl, 'template-body', 'insertAfter' );
    };
    return 1;
}

sub _edit_mtmljob_param {
    my ( $cb, $app, $param, $tmpl ) = @_;
    my $component = MT->component( 'Developer' );
    my $author = $app->user;
    if ( $author->is_superuser ) {
        # continue
    } else {
        $app->return_to_dashboard( permission => 1 );
        return;
    }
    if ( $app->blog ) {
        $app->return_to_dashboard();
        return;
    }
    my $obj;
    if ( my $id = $app->param( 'id' ) ) {
        $obj = MT->model( 'mtmljob' )->load( $id );
    }
    my $version = $component->get_config_value( 'developer_data_api_version' );
    $version =~ s/[^0-9]//g;
    $param->{ app_version } = $version;
    my $require_change_note = $component->get_config_value( 'require_change_note' );
    $param->{ require_change_note } = $require_change_note;
    if ( $obj ) {
        my $rn = $app->param( 'r' );
        if ( defined( $rn ) && $rn != $obj->current_revision ) {
            my $rev = $obj->load_revision( { rev_number => $rn } );
            if ( $rev && @$rev ) {
                $obj = $rev->[ 0 ];
                my $values = $obj->get_values;
                $param->{ $_ } = $values->{ $_ } foreach keys %$values;
                $param->{ loaded_revision } = 1;
            }
            $param->{ rev_number } = $rn;
        }
        $param->{ rev_date } = format_ts( '%Y-%m-%d %H:%M:%S',
        $obj->modified_on, undef,
        $app->user ? $app->user->preferred_language : undef );
        $param->{ evalscript } = $obj->evalscript;
    }
    if ( my $nextrun_on = $param->{ nextrun_on } ) {
        my $y = substr( $nextrun_on, 0, 4 );
        my $m = substr( $nextrun_on, 4, 2 );
        my $d = substr( $nextrun_on, 6, 2 );
        $param->{ nextrun_on_date } = "${y}-${m}-${d}";
        my $H = substr( $nextrun_on, 8, 2 );
        my $M = substr( $nextrun_on, 10, 2 );
        my $S = substr( $nextrun_on, 12, 2 );
        $param->{ nextrun_on_time } = "${H}:${M}:${S}";
    } else {
        # 20380119031407
        my @tl = offset_time_list( time, undef );
        my $ts = sprintf '%04d-%02d-%02d', $tl[ 5 ] + 1900, $tl[ 4 ] + 1, $tl[ 3 ];
        $param->{ nextrun_on_date } = $ts;
        $param->{ nextrun_on_time } = '00:00:00';
    }
    if ( $param->{ lastrun_on } ) {
        my $lastrun_on = $param->{ lastrun_on };
        $param->{ lastrun_on } = format_ts( '%Y-%m-%d@%H:%M:%S', $lastrun_on );
    }
    $param->{ ace_theme } = $component->get_config_value( 'developer_ace_theme' );
    $param->{ ace_font_size } = $component->get_config_value( 'developer_ace_font_size' );
    $param->{ ace_editor_height } = $component->get_config_value( 'developer_ace_editor_height' );
    $param->{ php_preview_url } = $component->get_config_value( 'developer_preview_php' );
    $param->{ ace_mtml_mode } = $component->get_config_value( 'developer_ace_mtml_mode' );
    if (! $param->{ id } ) {
        if ( $app->mode eq 'view' ) {
            my $eval = $component->get_config_value( 'developer_default_evalscript' );
            $param->{ evalscript } = $eval;
            $param->{ check_evalscript } = $eval;
            $param->{ status } = $component->get_config_value( 'developer_default_mtmljob_status' );
        }
    }
    if ( $app->mode ne 'view' ) {
        $param->{ 'revision-note' } = $app->param( 'revision-note' );
    }
    my $all_apps = MT->registry( 'applications' );
    my @apps_loop;
    push ( @apps_loop, { label => 'MT::App::CMS', app_name => 'MT::App::CMS' } );
    for my $mtapp( keys %$all_apps ) {
        if ( my $handler = $all_apps->{ $mtapp }->{ handler } ) {
            if ( $handler ne 'MT::App::CMS' ) {
                if ( $handler ne 'MT::App::Upgrader' ) {
                    push ( @apps_loop, { label => $handler, app_name => $handler } );
                }
            }
        }
    }
    # get_app_script
    my $interval = $param->{ interval };
    my $mt_app;
    if ( $interval && $interval == 10 ) {
        $mt_app = $param->{ app_ref };
    } elsif ( $interval && $interval == 9 ) {
        $mt_app = 'MT::App::Developer';
    } elsif ( $interval && $interval == 11 ) {
        $mt_app = 'MT::App::DataAPI';
    }
    if ( $mt_app ) {
        my $script = get_app_script( $mt_app );
        if ( $script ) {
            my @app_links;
            my $script_path = $script;
            $script = $app->base . $app->path . $script;
            if ( $interval && $interval == 10 ) {
                if ( my $detail = $param->{ detail } ) {
                    my @details = split( /,/, $detail );
                    for my $d ( @details ) {
                        push( @app_links, { link_url => $script . '?__mode=' . $d,
                                            link_label => $script_path . "?__mode=${d}",
                        } );
                    }
                }
            } elsif ( $interval && $interval == 9 ) {
                if ( my $basename = $param->{ basename } ) {
                    push( @app_links, { link_url => $script . '?basename=' . $basename,
                                        link_label => $component->translate( 'Application' ) . " ( ${script_path} )",
                    } );
                }
            } elsif ( $interval && $interval == 11 ) {
                if ( my $detail = $param->{ detail } ) {
                    if ( my $_script = $component->get_config_value( 'developer_data_api_endpoint' ) ) {
                        $script = $_script;
                    }
                    my ( $verb, $route ) = split( /,/, $detail );
                    if (! $route ) {
                        $verb = 'GET';
                        $route = $verb;
                    }
                    if ( $route =~ m!/:site_id/! ) {
                        my $website = MT->model( 'website' )->load( undef, { limit => 1 } );
                        my $site_id = $website->id;
                        $route =~ s/:site_id/$site_id/;
                        my @paths = split( /\//, $route );
                        for my $path ( @paths ) {
                            if ( $path =~ m/^:(.*)_id$/ ) {
                                if ( MT->model( $1 ) ) {
                                    my $obj;
                                    if ( MT->model( $1 )->has_column( 'blog_id' ) ) {
                                        $obj = MT->model( $1 )->load( { blog_id => $site_id },
                                                                      { limit => 1 } );
                                    } else {
                                        $obj = MT->model( $1 )->load( undef, { limit => 1 } );
                                    }
                                    if ( $obj ) {
                                        my $obj_id = $obj->id;
                                        $route =~ s!\/:.*?_id!/$obj_id!;
                                    }
                                }
                            }
                        }
                    }
                    $param->{ 'debugger_url' } = $component->translate( '__DebuggerURL' );
                    push( @app_links, { link_url => $script . "/v${version}",
                                        link_label => $component->translate( 'Data API Endpoint' ),
                    } );
                    push( @app_links, { link_url => $script . "/v${version}$route",
                                        link_label => $script_path . "/v${version}$route",
                    } );
                }
            }
            $param->{ app_links } = \@app_links;
        }
    }
    $param->{ apps_loop } = \@apps_loop;
    eval {
        require CustomFields::App::CMS;
        CustomFields::App::CMS::add_app_fields( $cb, $app, $param, $tmpl, 'status', 'insertAfter' );
    };
    if ( $app->param( 'reset_lastrun_on' ) ) {
        $param->{ reset_lastrun_on } = 1;
    }
    $param->{ screen_group } = 'mtmljob';
}

sub _pre_save_mtmljob {
    my ( $cb, $app, $obj, $original ) = @_;
    my $nextrun_on_date = $app->param( 'nextrun_on_date' );
    if (! $nextrun_on_date ) {
        my @tl = offset_time_list( time, undef );
        $nextrun_on_date = sprintf '%04d-%02d-%02d', $tl[ 5 ] + 1900, $tl[ 4 ]+1, $tl[ 3 ];
    }
    my $nextrun_on_time = $app->param( 'nextrun_on_time' );
    if (! $nextrun_on_time ) {
        $nextrun_on_time = '00:00:00';
    }
    $nextrun_on_date =~ s/[^0-9]//g;
    $nextrun_on_time =~ s/[^0-9]//g;
    my $nextrun_on = $nextrun_on_date . $nextrun_on_time;
    $obj->nextrun_on( $nextrun_on );
    if ( $app->param( 'reset_lastrun_on' ) ) {
        $obj->lastrun_on( undef );
    }
    my $interval = $obj->interval;
    if ( $interval && $interval == 11 ) {
        $obj->app_ref( 'MT::App::DataAPI' );
        $app->param( 'app_ref', 'MT::App::DataAPI' );
    } elsif ( (! $interval ) || ( $interval != 10 ) ) {
        if ( $interval != 9 ) {
            $app->delete_param( 'app_ref' );
            $obj->app_ref( undef );
        } else {
            $obj->app_ref( 'MT::App::Developer' );
            $app->param( 'app_ref', 'MT::App::Developer' );
        }
    }
    if ( (! $interval ) || ( $interval != 8 ) ) {
        $app->delete_param( 'tagkind' );
        $obj->tagkind( undef );
    }
    if ( $interval && ( $interval > 7 ) ) {
        $app->delete_param( 'priority' );
        $obj->priority( undef );
    }
    if ( $interval && ( $interval == 12 ) ) {
        $app->param( 'evalscript', 1 );
        $obj->evalscript( 1 );
    }
    1;
}

sub _post_save_mtmljob {
    my ( $cb, $app, $obj, $original ) = @_;
    my $component = MT->component( 'Developer' );
    my $message;
    if ( defined $original ) {
        $message = $component->translate( '[_1] \'[_2]\' (ID:[_3]) edited by \'[_4]\'',
            $obj->class_label, utf8_on( $obj->title ), $obj->id, $app->user->name );
    } else {
        $message = $component->translate( '[_1] \'[_2]\' (ID:[_3]) created by \'[_4]\'',
            $obj->class_label, utf8_on( $obj->title ), $obj->id, $app->user->name );
    }
    $app->log( {
        message => $message,
        author_id => $app->user->id,
        class => 'Custom Handler',
        level => MT::Log::INFO(),
    } );
    my $mt = MT->instance;
    $mt->reboot;
    return 1;
}

sub _post_save_alttemplate {
    my ( $cb, $app, $obj, $original ) = @_;
    my $component = MT->component( 'Developer' );
    my $message;
    if ( defined $original ) {
        $message = $component->translate( '[_1] \'[_2]\' (ID:[_3]) edited by \'[_4]\'',
            $obj->class_label, utf8_on( $obj->name ), $obj->id, $app->user->name );
    } else {
        $message = $component->translate( '[_1] \'[_2]\' (ID:[_3]) created by \'[_4]\'',
            $obj->class_label, utf8_on( $obj->name ), $obj->id, $app->user->name );
    }
    $app->log( {
        message => $message,
        author_id => $app->user->id,
        class => 'Alt Template',
        level => MT::Log::INFO(),
    } );
    return 1;
}

sub _post_delete_object {
    my ( $cb, $app, $obj, $original ) = @_;
    my $component = MT->component( 'Developer' );
    my $title;
    if ( $obj->has_column( 'title' ) ) {
        $title = $obj->title;
    } else {
        $title = $obj->name;
    }
    my $message = $component->translate( '[_1] \'[_2]\' (ID:[_3]) deleted by \'[_4]\'',
            $obj->class_label, utf8_on( $title ), $obj->id, $app->user->name );
    $app->log( {
        message => $message,
        author_id => $app->user->id,
        class => $obj->class_label_raw,
        level => MT::Log::INFO(),
    } );
    return 1;
}

sub _search_mtmljobs {
    my $app = shift;
    my $component = MT->component( 'Developer' );
    my ( %args ) = @_;
    my $iter;
    if ( $args{ iter } ) {
        $iter = $args{ iter };
    } elsif ( $args{ items } ) {
        $iter = sub { pop @{ $args{ items } } };
    }
    return [] unless $iter;
    my $limit = $args{ limit };
    my $param = $args{ param } || {};
    my @data;
    while ( my $obj = $iter->() ) {
        my $interval = $obj->interval;
        my $row = $obj->column_values;
        $row->{ object } = $obj;
        my $columns = $obj->column_names;
        for my $column ( @$columns ) {
            my $val = $obj->$column;
            if ( $column eq 'nextrun_on' ) {
                if (! $val ) {
                    $val = '-';
                } else {
                    if ( ( defined $interval ) && ( $interval == 2 ) ) {
                        $val = format_ts( '%Y-%m-%d@%H:%M:%S', $val );
                    } else {
                        if ( $interval == 0 ) {
                            $val = '-';
                        } else {
                            $val = format_ts( '@%H:%M:%S', $val );
                        }
                    }
                }
            } else {
                if ( $column eq 'interval' ) {
                    # $val = __get_interval( $val );
                    $val = $obj->interval_text;
                } elsif ( $column eq 'status' ) {
                    $val = $obj->status_text;
                    # $val = $component->translate( 'Enabled' ) if $val == 2;
                    # $val = $component->translate( 'Disabled' ) if $val == 1;
                }
            }
            $row->{ $column } = $val;
        }
        my $author = $obj->author;
        $row->{ _author_name } = $author->nickname;
        push @data, $row;
        last if $limit and @data > $limit;
    }
    $param->{ search_label } = $component->translate( 'Custom Handle' );
    return [] unless @data;
    $app->{ plugin_template_path } = File::Spec->catdir( $component->path, 'tmpl' );
    $param->{ search_replace } = 1;
    $param->{ object_loop } = \@data;
    \@data;
}

sub _search_alttemplate {
    my $app = shift;
    my $component = MT->component( 'Developer' );
    my ( %args ) = @_;
    my $iter;
    if ( $args{ iter } ) {
        $iter = $args{ iter };
    } elsif ( $args{ items } ) {
        $iter = sub { pop @{ $args{ items } } };
    }
    return [] unless $iter;
    my $limit = $args{ limit };
    my $param = $args{ param } || {};
    my @data;
    while ( my $obj = $iter->() ) {
        my $row = $obj->column_values;
        $row->{ object } = $obj;
        my $columns = $obj->column_names;
        for my $column ( @$columns ) {
            my $val = $obj->$column;
            if ( $column eq 'status' ) {
                $val = $obj->status_text;
            }
            $row->{ $column } = $val;
        }
        my $author = $obj->author;
        $row->{ _author_name } = $author->nickname;
        push @data, $row;
        last if $limit and @data > $limit;
    }
    $param->{ search_label } = $component->translate( 'Alt Template' );
    return [] unless @data;
    $app->{ plugin_template_path } = File::Spec->catdir( $component->path, 'tmpl' );
    $param->{ search_replace } = 1;
    $param->{ object_loop } = \@data;
    \@data;
}

sub _install_sign_in_template {
    my $app = shift;
    if (! $app->user->is_superuser ) {
        return $app->trans_error( 'Permission denied.' );
    }
    if (! $app->validate_magic ) {
        return $app->trans_error( 'Permission denied.' );
    }
    my $component = MT->component( 'Developer' );
    require File::Spec;
    my $tmpl_path = File::Spec->catdir( $app->mt_dir, 'tmpl' );
    my $res = '';
    require MT::FileMgr;
    require File::Basename;
    $app->param( 'save_revision', 1 );
    $app->param( 'current_revision', 0 );
    $app->param( 'revision-note', $component->translate( 'First Commit.' ) );
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    # my @tmplates = qw( cms/dialog/recover cms/error
    #     comment/profile comment/signup comment/signup_thanks );
    # # cms/login
    # for my $tmpl ( @tmplates ) {
    #     my @paths = split( /\//, $tmpl );
    #     my $path = File::Spec->catfile( $tmpl_path, @paths );
    #     my $basename = File::Basename::basename( $path );
    #     my $data = $fmgr->get_data( $path . '.tmpl' );
    #     my $alt_tmpl = MT->model( 'alttemplate' )->get_by_key( { 'app_ref' => 'MT::App::Developer',
    #                                                               template => $basename } );
    #     my $original = $alt_tmpl->clone();
    #     $alt_tmpl->text( $data );
    #     $alt_tmpl->name( $component->translate( '__' . $basename ) );
    #     # Set status?
    #     if (! $alt_tmpl->status ) {
    #         $alt_tmpl->status( 2 );
    #     }
    #     $app->run_callbacks( 'cms_pre_save.alttemplate', $app, $alt_tmpl, $original );
    #     $alt_tmpl->save or die $alt_tmpl->errstr;
    #     $app->run_callbacks( 'cms_post_save.alttemplate', $app, $alt_tmpl, $original );
    # }
    my @tmplates = qw( email_verification_email commenter_notify
                       login recover profile signup signup_thanks error );
    $tmpl_path = File::Spec->catdir( $component->path, 'tmpl' );
    for my $tmpl ( @tmplates ) {
        my $path = File::Spec->catfile( $tmpl_path, $tmpl );
        my $data = $fmgr->get_data( $path . '.tmpl' );
        my $basename = $tmpl;
        my $alt_tmpl = MT->model( 'alttemplate' )->get_by_key( { 'app_ref' => 'MT::App::Developer',
                                                                  template => $basename } );
        my $original = $alt_tmpl->clone();
        $alt_tmpl->text( $data );
        if (! $alt_tmpl->status ) {
            $alt_tmpl->status( 2 );
        }
        $alt_tmpl->name( $component->translate( '__' . $basename ) );
        $app->run_callbacks( 'cms_pre_save.alttemplate', $app, $alt_tmpl, $original );
        $alt_tmpl->save or die $alt_tmpl->errstr;
        $app->run_callbacks( 'cms_post_save.alttemplate', $app, $alt_tmpl, $original );
    }
    my $return_url = $app->uri . $app->uri_params( mode => 'list',
                                args => { _type => 'alttemplate', installed => 1 });
    return $app->redirect( $return_url );
}

# tmpl/cms/login.tmpl
# tmpl/cms/error.tmpl 
# tmpl/cms/dialog/recover.tmpl
# tmpl/comment/profile.tmpl 
# tmpl/comment/signup.tmpl
# tmpl/comment/signup_thanks.tmpl
# Plugins/Developer/tmpl/email_verification_email.tmpl
# Plugins/Developer/tmpl/commenter_notify.tmpl 

sub _set_ace_settings_as_default {
    my $app = shift;
    if (! $app->user->is_superuser ) {
        return $app->trans_error( 'Permission denied.' );
    }
    if ( $app->request_method ne 'POST' ) {
        return $app->trans_error( 'Permission denied.' );
    }
    if (! $app->validate_magic ) {
        return $app->trans_error( 'Permission denied.' );
    }
    my $component = MT->component( 'Developer' );
    my $params = $app->param( 'params' );
    my @settings = split( /,/, $params );
    $component->set_config_value( 'developer_ace_theme', $settings[ 0 ] );
    $component->set_config_value( 'developer_ace_font_size', $settings[ 1 ] );
    $component->set_config_value( 'developer_ace_editor_height', $settings[ 2 ] );
    $component->set_config_value( 'developer_ace_mtml_mode', $settings[ 3 ] );
    return '';
}

sub _add_link_to_revision {
    my ( $cb, $app, $template ) = @_;
    my $search = quotemeta( '<__trans phrase="View revisions"></a>' );
    my $insert = <<'HTML';
<__trans_section component="Developer">
    <mt:setvarblock name="next_return_url"><mt:var name="script_url">?__mode=list_revision&_type=<mt:var name="object_type">&id=<$mt:var name="id" escape="html"$>&blog_id=<$mt:var name="blog_id"$>&r=<mt:var name="rev_number" escape="html"></mt:setvarblock>
      <div><a href="javascript:void(0);" onclick="window.open('<mt:var name="script_url">?__mode=show_revision_diff&current_revision=<mt:var name="current_revision" escape="html">&_type=<mt:var name="object_type">&id=<$mt:var name="id" escape="html"$>&blog_id=<$mt:var name="blog_id"$>&return_url=<mt:var name="next_return_url" escape="url">&r=<mt:var name="current_revision" escape="html">', 'revision-<mt:var name="object_type" escape="html">-<mt:var name="id" escape="html">', 'width=640, height=640, menubar=no, toolbar=no, scrollbars=yes');" title="<__trans phrase="View Latest Changes in new Window">">
<__trans phrase="View Latest Changes"></a></div>
</__trans_section>
HTML
    $$template =~ s/($search)/$1$insert/g;
}

sub _set_revision_title {
    my ( $cb, $app, $template ) = @_;
    my $model = $app->param( '_type' );
    my $id = $app->param( 'id' );
    if ( $model && $id ) {
        if ( my $obj = MT->model( $model )->load( $id ) ) {
            my $search = quotemeta( '<__trans phrase="Revision History">' );
            my $title;
            if ( $obj->has_column( 'title' ) ) {
                $title = $obj->title;
            } else {
                $title = $obj->name;
            }
            my $insert = encode_html( $title );
            my $class_label = encode_html( $obj->class_label );
            my $_title = MT->translate( 'Revision History' );
            if ( $$template =~ s/($search)/$class_label $1 - $insert/ ) {
                # <button
                $search = quotemeta( '<button' );
                $insert = <<HTML;

                onclick="window.close();"
HTML
                if (! $app->param( 'dialog' ) ) {
                    $$template =~ s/($search)/$1$insert/;
                }
            }
            $$template =~ s!(<title>).*?(</title>)!$1$class_label $_title - $insert$2!;
        }
    }
}

sub _add_column_to_revision {
    my ( $cb, $app, $template ) = @_;
    my $search = quotemeta( '<__trans phrase="Saved By"></span></th>' );
    my $insert = '<th class="col head" style="width:50px"><span class="col-label"><__trans phrase="Diff"></span></th>';
    $$template =~ s/($search)/$1$insert/;
    $search = quotemeta( '<mt:var name="created_by" escape="html"></span></td>' );
    $insert = <<HTML;
      <td class="col"><mt:if name="rev_has_update"><a class="revision-number" href="javascript:void(0);" onclick="javascript:<mt:var name="rev_diff"\>;"><__trans phrase="Diff"></a></mt:if></td>
HTML
    $$template =~ s/($search)/$1$insert/;
    $search = quotemeta( '<mt:if name="object_type" like="(entry|page)">' );
    $insert = '<mt:if name="has_status">';
    $$template =~ s/$search/$insert/g;
    $search = quotemeta( '<th class="col head status">' );
    $insert = '<th class="col head status" style="width:84px">';
    $$template =~ s/$search/$insert/g;
    $$template = '<__trans_section component="Developer">' . $$template . '</__trans_section>';
}

sub _add_params_to_revision {
    my ( $cb, $app, $params, $tmpl ) = @_;
    my $class = $app->param( '_type' );
    if ( my $model = MT->model( $class ) ) {
        $params->{ has_status } = $model->has_column( 'status' );
    }
}

sub _pre_listing_revision {
    my ( $cb, $app, $terms, $args, $params, $hasher ) = @_;
    my $blog_id  = $app->param( 'blog_id' );
    my $id = $app->param( 'id' );
    my $type = $app->param( '_type' );
    my $class = $app->model( $type );
    my $param = $args->{ param };
    my $obj = $class->load( $id );
    my $blog = $app->blog;
    my $lang = $app->user->preferred_language;
    my $js_base = "location.href='";
    if (! $app->param( 'dialog' ) ) {
        $js_base = "window.opener.location.href='";
    }
    my $js = $js_base . $app->uri . $app->uri_params( mode => 'view',
                                 args => { _type => $type,
                                           blog_id => $blog_id,
                                           id => $id } );
    my $rev_js = "location.href='" . $app->uri . $app->uri_params( mode => 'show_revision_diff',
                                 args => { _type => $type,
                                           blog_id => $blog_id,
                                           id => $id,
                                           current_revision => $obj->current_revision } );
    $rev_js .= '&return_url=' . encode_url( $app->uri . '?' . $app->query_string );
    if ( $app->param( 'dialog' ) ) {
        $rev_js .= '&dialog=1';
    }
    $$hasher = sub {
        my ( $rev, $row ) = @_;
        if ( my $ts = $rev->created_on ) {
            $row->{ created_on_formatted } = format_ts( 
                MT::App::CMS::LISTING_DATE_FORMAT(), $ts, $blog, $lang );
            $row->{ created_on_time_formatted } = format_ts(
                MT::App::CMS::LISTING_TIMESTAMP_FORMAT(), $ts, $blog, $lang );
            $row->{ created_on_relative } = MT::Util::relative_date( $ts, time(), $blog );
        }
        if ( my $author_id = $row->{ created_by } ) {
            my $created_user = MT::Author->load( $author_id );
            if ( $created_user ) {
                $row->{ created_by } = $created_user->nickname;
            } else {
                $row->{ created_by } = $app->translate( '(user deleted)' );
            }
        }
        my $revision = $obj->object_from_revision( $rev );
        my $column_defs = $obj->column_defs;
        if ( $obj->has_column( 'status' ) ) {
            $row->{ rev_status } = $revision->[ 0 ]->status;
        }
        # if ( $type eq 'mtmljob' ) {
            my $rev_number = $row->{ rev_number };
            if ( my $rev_new = $obj->load_revision( { rev_number => $rev_number } ) ) {
                $rev_new = $rev_new->[ 0 ];
                my $obj_old  = $obj->load_revision( { rev_number => $rev_number - 1 } );
                $obj_old = $obj_old->[ 0 ] if $obj_old;
                my ( $text_new, $text_old, $more_new, $more_old );
                $text_old = '';
                $more_old = '';
                $text_new = '';
                $more_new = '';
                my $object_title;
                if ( $obj->has_column( 'text' ) ) {
                    $text_new = $rev_new->text;
                    $text_old = $obj_old->text if $obj_old;
                } elsif ( $obj->has_column( 'body' ) ) {
                    # CustomObject
                    $text_new = $rev_new->body;
                    $text_old = $obj_old->body if $obj_old;
                }
                if ( ( $text_old ne $text_new ) || ( $more_old ne $more_new ) ) {
                    $row->{ rev_has_update } = 1;
                }
            }
        # }
        $row->{ rev_js } = $js . '&amp;r=' . $row->{ rev_number } . "'";
        $row->{ rev_diff } = $rev_js . '&amp;r=' . $row->{ rev_number } . "'";
        my $r = $app->param( 'r' ) || $revision->[ 0 ]->current_revision;
        $row->{ is_current } = $r == $row->{ rev_number };
        if ( $row->{ rev_number } > $r ) {
            $row->{ has_next } = 1;
        }
    };
}

sub _show_revision_diff {
    my $app = shift;
    my $component = MT->component( 'Developer' );
    my $type = $app->param( '_type' );
    my $id = $app->param( 'id' );
    my $blog_id = $app->param( 'blog_id' );
    my $rev = $app->param( 'r' );
    # $app->call_return if $rev == 1;
    return $app->errtrans( 'Invalid request.' ) unless $type;
    my $class = $app->model( $type ) or return $app->errtrans( 'Invalid type [_1]', $type );
    return $app->error( $app->translate( 'No ID' ) ) if !$id;
    $id =~ s/\D//g;
    require MT::Promise;
    my $obj_promise = MT::Promise::delay(
        sub {
            return $class->load( $id ) || undef;
        }
    );
    $app->run_callbacks( 'cms_view_permission_filter.' . $type, $app, $id, $obj_promise )
            || return $app->permission_denied();
    my $obj = $obj_promise->force();
    my %param;
    # my $rev_new = $obj->load_revision( { rev_number => $rev } );
    my $rev_new = __load_revision( $obj, { rev_number => $rev } );
    my $note = $rev_new->[ 3 ]->description if $rev_new;
    my $obj_new = $rev_new->[ 0 ];
    my $old = $rev - 1;
    my $rev_old = $obj->load_revision( { rev_number => $old } );
    my $obj_old = $rev_old->[ 0 ];
    my ( $text_new, $text_old, $more_new, $more_old );
    $text_old = '';
    $more_old = '';
    $text_new = '';
    $more_new = '';
    my $object_title;
    if ( $obj->has_column( 'title' ) ) {
        $object_title = $obj->title;
    } elsif ( $obj->has_column( 'name' ) ) {
        $object_title = $obj->name;
    }
    if ( $obj->has_column( 'text' ) ) {
        $text_new = $obj_new->text;
        $text_old = $obj_old->text if $obj_old;
    } elsif ( $obj->has_column( 'body' ) ) {
        # CustomObject
        $text_new = $obj_new->body;
        $text_old = $obj_old->body if $obj_old;
    }
    if ( $obj_new->has_column( 'created_by' ) ) {
        if ( my $author_id = $obj_new->created_by ) {
            my $created_user = MT::Author->load( $author_id );
            if ( $created_user ) {
                $param{ created_by } = $created_user->nickname;
            } else {
                $param{ created_by } = $app->translate( '(user deleted)' );
            }
        }
    }
    require Text::Diff;
    my $diff = Text::Diff::diff( \$text_old, \$text_new );
    if ( ( $type eq 'entry' ) || ( $type eq 'page' ) ) {
        $more_new = $obj_new->text_more;
        $more_old = $obj_old->text_more if $obj_old;
        $param{ show_more } = 1;
        $param{ text_label } = MT->translate( 'Entry Body' );
        $param{ more_label } = MT->translate( 'Extended Entry' );
    } elsif ( ( $type eq 'template' ) || ( $type eq 'alttemplate' ) ) {
        $param{ text_label } = MT->translate( 'Text' );
    } elsif ( $type eq 'mtmljob' ) {
        if ( ( $obj_new->interval == 8 ) || ( $obj_old &&( $obj_old->interval == 8 ) ) ) {
            $more_new = $obj_new->text_php;
            $more_old = $obj_old->text_php if $obj_old;
            $param{ show_more } = 1;
        }
        if ( $obj_new->interval == 12 ) {
            $param{ 'text_label' } = $component->translate( 'YAML Document' );
        } else {
            if ( $obj->evalscript ) {
                $param{ text_label } = $component->translate( 'Perl Code' );
            } else {
                $param{ text_label } = $component->translate( 'MTML Code' );
            }
        }
        $param{ more_label } = $component->translate( 'PHP Code' );
    }
    my $diff_more = Text::Diff::diff( \$more_old, \$more_new );
    $param{ revision_diff } = $diff;
    $param{ ace_theme } = $component->get_config_value( 'developer_ace_theme' );
    $param{ ace_font_size } = $component->get_config_value( 'developer_ace_font_size' );
    $param{ ace_editor_height } = $component->get_config_value( 'developer_ace_editor_height' );
    $param{ revision_diff_more } = $diff_more;
    $param{ old_rev_num } = $old;
    $param{ rev_num } = $rev;
    $param{ class_label } = $obj->class_label;
    # return Dumper $obj;
    $param{ description } = $note;
    $param{ return_url } = $app->param( 'return_url' );
    my $tmpl = File::Spec->catfile( $component->path, 'tmpl', 'dialog', 'show_revision_diff.tmpl' );
    my $html = $app->build_page( $tmpl, \%param );
    my $page_title = $object_title .
         ' - ' . $component->translate( 'Change between rev.[_1] and rev.[_2]', $old, $rev );
    $page_title = encode_html( $page_title );
    $html =~ s!(<title>).*?(</title>)!$1$page_title$2!;
    return $html;
    # return '<pre> ' . encode_html( $diff );
}

sub __load_revision {
    # my $driver = shift;
    my ( $obj, $terms, $args ) = @_;
    my $datasource = $obj->datasource;
    my $rev_class  = MT->model( $datasource . ':revision' );
    # Only specified a rev_number
    if ( defined $terms && ref $terms ne 'HASH' ) {
        $terms = { rev_number => $terms };
    }
    $terms->{ $datasource . '_id' } ||= $obj->id;
    if ( wantarray ) {
        my @rev = map { __object_from_revision( $obj, $_ ); }
            $rev_class->load( $terms, $args );
        unless ( @rev ) {
            return $obj->error( $rev_class->errstr );
        }
        return @rev;
    } else {
        my $rev = $rev_class->load( $terms, $args )
            or return $obj->error( $rev_class->errstr );
        my $array = __object_from_revision( $obj, $rev );
        return $array;
    }
}

sub __object_from_revision {
    # my $driver = shift;
    my ( $obj, $rev ) = @_;
    my $datasource = $obj->datasource;
    my $rev_obj = $obj->clone;
    my $serialized_obj = $rev->$datasource;
    require MT::Serialize;
    my $packed_obj = MT::Serialize->unserialize($serialized_obj);
    $rev_obj->unpack_revision($$packed_obj);
    # Here we cheat since audit columns aren't revisioned
    $rev_obj->modified_by( $rev->created_by );
    $rev_obj->modified_on( $rev->modified_on );
    my @changed = split ',', $rev->changed;
    return [ $rev_obj, \@changed, $rev->rev_number, $rev ];
}

1;