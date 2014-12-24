<?php
    $mt = MT::get_instance();
    $ctx =& $mt->context();
    $app = $ctx->stash( 'bootstrapper' );
    if ( $app ) {
        $templates_c = $app->stash( 'templates_c' );
    } else {
        $templates_c = $ctx->compile_dir;
        $plugin_dir = dirname( __FILE__ ) . DIRECTORY_SEPARATOR . 'tags';
        if ( is_dir( $plugin_dir ) ) {
            $mt->load_plugin( $plugin_dir );
            $ctx->add_plugin_dir( $plugin_dir );
        }
    }
    if ( $templates_c && is_writable( $templates_c ) ) {
        $lib = $templates_c . DIRECTORY_SEPARATOR . 'smarty_tags_developer_tags.php';
        if ( file_exists( $lib ) ) {
            require_once( 'MTUtil.php' );
            $ts = offset_time_list( filemtime( $lib ) );
            $ts = sprintf( "%04d%02d%02d%02d%02d%02d",
                $ts[5]+1900, $ts[4]+1, $ts[3], $ts[2], $ts[1], $ts[0] );
        }
    }
    $block_tags = array();
    $modifiers = array();
    $modifiers_mtml = array();
    require_once( 'class.mt_mtmljob.php' );
    $mtmljob = new MTMLJob;
    $jobs = $mtmljob->Find( 'mtmljob_status=2 and mtmljob_interval=8' );
    if (! is_array( $jobs ) ) {
        return;
    }
    foreach ( $jobs as $job ) {
        $tag = strtolower( $job->detail );
        if ( $job->tagkind != 'modifier' )  {
            if ( strpos( $tag, 'mt' ) !== FALSE ) {
                $tag = preg_replace( '/^mt:{0,1}/', '', $tag );
            }
        }
        $modified_on = $mt->db()->db2ts( $job->modified_on );
        if ( $ts && ( $ts < $modified_on ) ) {
            $unlink = 1;
        }
        $text_php = $job->mtmljob_text_php;
        $text_php =ltrim( $text_php );
        if ( $job->evalphp )  {
            if ( preg_match( "/^function/", $text_php ) ) {
                $text_php = preg_replace(
                "/^function[^\{]{0,}/",
                "",
                $text_php );
                $text_php = ltrim( $text_php, '{' );
                $text_php = rtrim( $text_php );
                $text_php = rtrim( $text_php, '}' );
            }
        }
        if ( $job->tagkind != 'modifier' ) {
            if ( $job->evalphp )  {
                if ( $job->tagkind == 'function' ) {
                    $ctx->stash( 'developer_function_tag_mt' . $tag, $text_php );
                    $ctx->add_tag( $tag, 'developer_function_tags' );
                } else {
                    $ctx->stash( 'developer_block_tag_mt' . $tag, $text_php );
                    if ( $job->tagkind == 'block' ) {
                        $ctx->add_container_tag( $tag, 'developer_block_tags' );
                    } elseif ( $job->tagkind == 'conditional' ) {
                        $ctx->add_conditional_tag( $tag, 'developer_conditional_tags' );
                    }
                }
            } else {
                if ( $job->tagkind == 'function' ) {
                    $ctx->stash( 'developer_function_mtml_tag_mt' . $tag, $job->text );
                    $ctx->add_tag( $tag, 'developer_function_mtml_tags' );
                } else {
                    $ctx->stash( 'developer_block_mtml_tag_mt' . $tag, $job->text );
                    if ( $job->tagkind == 'conditional' ) {
                        $ctx->add_conditional_tag( $tag, 'developer_block_mtml_tags' );
                    } else {
                        $ctx->add_container_tag( $tag, 'developer_block_mtml_tags' );
                    }
                }
            }
        } elseif ( $job->tagkind == 'modifier' ) {
            if ( $job->evalphp ) {
                $modifiers[ $tag ] = array( $job->id, $text_php );
            } else {
                $modifiers_mtml[ $tag ] = array( $job->id, $job->text );
            }
        }
    }
    if ( $modifiers ) {
        $modifier_code_tmpl = dirname( __FILE__ ) .
            DIRECTORY_SEPARATOR . 'tmpl' . DIRECTORY_SEPARATOR . 'modifier_code.tmpl';
        if ( file_exists( $modifier_code_tmpl ) ) {
            $modifier_code_tmpl = file_get_contents( $modifier_code_tmpl );
        } else {
            $modifier_code_tmpl = NULL;
        }
    }
    if ( $modifiers_mtml ) {
        $modifier_tmpl = dirname( __FILE__ ) .
            DIRECTORY_SEPARATOR . 'tmpl' . DIRECTORY_SEPARATOR . 'modifier.tmpl';
        if ( file_exists( $modifier_tmpl ) ) {
            $modifier_tmpl = file_get_contents( $modifier_tmpl );
        } else {
            $modifier_tmpl = NULL;
        }
    }
    if ( $lib ) {
        if ( $unlink && file_exists( $lib ) ) {
            unlink( $lib );
        }
        if (! file_exists( $lib ) || $ctx->force_compile ||
                $mt->config( 'DynamicForceCompile' ) ) {
            $code = '';
            if ( $modifier_code_tmpl ) {
                foreach ( $modifiers as $tag => $arr ) {
                    $id = $arr[ 0 ];
                    $text_php = $arr[ 1 ];
                    $modifier_code_tmpl = str_replace( '<ID>', $id, $modifier_code_tmpl );
                    $ctx->stash( 'developer_modifier_modifier_id_' . $id, $text_php );
                    $func = 'smarty_modifier_' . $tag;
                    $ctx->add_global_filter( strtolower( $tag ), $func );
                    $code  .= "function ${func} ( \$text, \$arg ) {\n";
                    $code .= $modifier_code_tmpl;
                    $code .= "\n}\n";
                }
            }
            if ( $modifier_tmpl ) {
                foreach ( $modifiers_mtml as $tag => $arr ) {
                    $id = $arr[ 0 ];
                    $text = $arr[ 1 ];
                    $modifier_tmpl = str_replace( '<ID>', $id, $modifier_tmpl );
                    $ctx->stash( 'developer_modifier_modifier_id_' . $id, $text );
                    $func = 'smarty_modifier_' . $tag;
                    $ctx->add_global_filter( strtolower( $tag ), $func );
                    $code  .= "function ${func} ( \$text, \$arg ) {\n";
                    $code .= $modifier_tmpl;
                    $code .= "\n}\n";
                }
            }
            if ( $code ) {
                $code = "<?php\n" . $code . "?>";
                if ( $app ) {
                    if ( $app->content_is_updated( $lib, $code ) ) {
                        $app->put_data( $code, $lib );
                    }
                } else {
                    file_put_contents( $lib, $code );
                }
            }
        }
    }
    if ( file_exists( $lib ) ) {
        require_once( $lib );
    }
    function developer_function_tags ( $args, &$ctx ) {
        $tag = $ctx->this_tag();
        $src = $ctx->stash( 'developer_function_tag_' . $tag );
        return eval( $src );
    }
    function developer_block_tags ( $args, $content, &$ctx, &$repeat ) {
        $tag = $ctx->this_tag();
        $src = $ctx->stash( 'developer_block_tag_' . $tag );
        return eval( $src );
    }
    function developer_conditional_tags ( $args, $content, &$ctx, &$repeat ) {
        $tag = $ctx->this_tag();
        $src = $ctx->stash( 'developer_block_tag_' . $tag );
        return eval( $src );
    }
    function developer_function_mtml_tags ( $args, &$ctx ) {
        $tag = $ctx->this_tag();
        $tmpl = $ctx->stash( 'developer_function_mtml_tag_' . $tag );
        require_once( 'modifier.mteval.php' );
        $contents = smarty_modifier_mteval( $tmpl, TRUE );
        return $contents;
    }
    function developer_block_mtml_tags ( $args, $content, &$ctx, &$repeat ) {
        $tag = $ctx->this_tag();
        $tmpl = $ctx->stash( 'developer_block_mtml_tag_' . $tag );
        require_once( 'modifier.mteval.php' );
        if ( strpos( $tag, 'mtif' ) !== FALSE ) {
            $contents = smarty_modifier_mteval( $tmpl, TRUE );
            if ( strpos( $tag, 'mtif' ) !== FALSE ) {
                if ( $contents ) {
                    return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
                } else {
                    return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
                }
            }
        } else {
            if (! isset ( $content ) ) {
                $repeat = TRUE;
            } else {
                $repeat = FALSE;
                $ctx->__stash[ 'vars' ][ '__content__' ] = $content;
                $contents = smarty_modifier_mteval( $tmpl, TRUE );
                return $contents;
            }
        }
        // return $contents;
    }
?>