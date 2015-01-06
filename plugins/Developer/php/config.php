<?php
class Developer extends MTPlugin {
    var $app;
    var $registry = array(
        'name' => 'Developer',
        'id'   => 'Developer',
        'key'  => 'developer',
        'config_settings' => array(
            'SpeedMeterDebugScope' => array( 'default' => 'log' ),//Start not export
            'DeveloperScript' => array( 'default' => 'mt-app.cgi' ),
//End not export
            'AllowPHPScript' => array( 'default' => 0 ),
            'PathToRelative' => array( 'default' => 0 ),
            'CanWriteTo' => array( 'default' => '' ),
            'CanReadFrom' => array( 'default' => '' ),
            'ForceTargetOutLink' => array( 'default' => 0 ),
            'AllowThrowSQL' => array( 'default' => 0 ),
            'OnetimeTokenTTL' => array( 'default' => 600 ),
        ),
        'tags' => array(
            'block' => array( 'phpscript'  => '_hdlr_phpscript',
                              'evalscript' => '_hdlr_phpscript',
                              'setpropertyblock' => '_hdlr_setproperty_block',
                              'cacheproperty' => '_hdlr_cacheproperty',
                              'ifproperty' => '_hdlr_if_property',
                              'ifregexmatch' => '_hdlr_if_regexmatch',
                              'ifuserrole' => '_hdlr_if_userrole',
                              'ifusercan' => '_hdlr_if_usercan',
                              'ifrequestmethod' => '_hdlr_if_request_method',
                              'ifvalidatemagic' => '_hdlr_if_validate_magic',
                              'ifvalidtoken' => '_hdlr_if_validtoken',
                              'speedmeter' => '_hdlr_speedmeter',
                              'countgroupby' => '_hdlr_countgroupby',
                              'build' => '_hdlr_build',
                              'clearcontext' => '_hdlr_clearcontext',
                              'csscompressor'=> '_hdlr_csscompressor',
                              'fileinfo' => '_hdlr_fileinfo',
                              'fileinfoloop' => '_hdlr_fileinfoloop',
                              'htmlcompressor' => '_hdlr_htmlcompressor',
                              'ifcookie' => '_hdlr_if_cookie',
                              'ifentryisincategory' => '_hdlr_if_entryisincategory',
                              'ifheader' => '_hdlr_if_header',
                              'iflanguage' => '_hdlr_if_language',
                              'iftheurlfound' => '_hdlr_if_theurlfound',
                              'jscompressor' => '_hdlr_jscompressor',
                              // 'json2mtml' => '_hdlr_json2mtml',
                              'setcontext' => '_hdlr_setcontext',
                              // 'varsrecurse' => '_hdlr_varsrecurse',
                               ),
         'function' => array( 'sendmail' => '_hdlr_sendmail',
                              'copyfileto' => '_hdlr_copyfileto',
                              'movefileto' => '_hdlr_movefileto',
                              'copydirectoryto' => '_hdlr_copyfileto',
                              'movedirectoryto' => '_hdlr_movefileto',
                              'writetofile' => '_hdlr_writetofile',
                              'readfromfile' => '_hdlr_readfromfile',
                              'removefile' => '_hdlr_removefile',
                              'removedirectory' => '_hdlr_removefile',
                              'setproperty' => '_hdlr_setproperty',
                              'getproperty' => '_hdlr_getproperty',
                              'deleteproperty' => '_hdlr_deleteproperty',
                              'countgroupcount' => '_hdlr_countgroupcount',
                              'countgroupvalue' => '_hdlr_countgroupvalue',
                              'assetthumbnailfile' => '_hdlr_assetthumbnailfile',
                              'buildlink' => '_hdlr_buildlink',
                              'requestmethod' => '_hdlr_request_method',
                              'clearcookie' => '_hdlr_clearcookie',
                              'cookiedump' => '_hdlr_cookiedump',
                              'envdump' => '_hdlr_envdump',
                              'developerscript' => '_hdlr_developerscript',
                              'getcookie' => '_hdlr_getcookie',
                              'getenv' => '_hdlr_getenv',
                              'getepoc' => '_hdlr_getepoc',
                              'getheader' => '_hdlr_getheader',
                              'geturlmtime' => '_hdlr_geturlmtime',
                              'log' => '_hdlr_log',
                              'mljob' => '_hdlr_mljob',
                              'customhandler' => '_hdlr_mljob',
                              'mljobtitle' => '_hdlr_mljobtitle',
                              'mljobname' => '_hdlr_mljobtitle',
                              'customhandlertitle' => '_hdlr_mljobtitle',
                              'customhandlername' => '_hdlr_mljobtitle',
                              'query2log' => '_hdlr_query2log',
                              'querydump' => '_hdlr_querydump',
                              'setcolumns2vars' => '_hdlr_setcolumns2vars',
                              'setcooki' => '_hdlr_setcookie',
                              'setfields2vars' => '_hdlr_setfields2vars',
                              'throwsql' => '_hdlr_throwsql',
                              'translate' => '_hdlr_translate',
                              'vardump' => '_hdlr_vardump',
                              'magictoken' => '_hdlr_magic_token',
                              'getonetimetoken' => '_hdlr_get_onetimetoken',
                              ),
         'modifier' => array( 'convert2base64' => '_filter_convert2base64',
                              'outiftheurlfound' => '_filter_outiftheurlfound',
                              ),

        ),
    );

    function tags_dir () {
        return dirname( __FILE__ ) . DIRECTORY_SEPARATOR . 'tags' . DIRECTORY_SEPARATOR;
    }

// <MTCountGroupBy model="entry" not_null="1" column="keywords" sort_by="count" sort_order="descend">
// <MTIf name="__first__"><ul></MTIf>
// <li>(<$MTCountGroupCount$>)<$MTCountGroupValue escape="html"$></li>
// <MTIf name="__last__"></ul></MTIf>
// </MTCountGroupBy>
// SELECT COUNT(*) AS cnt, entry_keywords
// FROM mt_entry
// WHERE (entry_keywords != '') AND (entry_status = '2') AND (entry_class = 'entry') AND (entry_blog_id IN ('1'))
// GROUP BY entry_keywords

    function _hdlr_countgroupby ( $args, $content, &$ctx, &$repeat ) {
        $localvars = array( 'row', 'rows', '_group_count', '_group_counter', '_col_name' );
        $app = $ctx->stash( 'bootstrapper' );
        if (! isset( $content ) ) {
            $ctx->localize( $localvars );
            $ctx->__stash[ 'fis' ] = NULL;
        }
        if (! isset( $content ) ) {
            $model = $app->escape( $args[ 'model' ] );
            if ( $model == 'author' ) {
                return '';
            }
            if (! $model ) $model = 'entry';
            require_once( 'class.mt_' . $model . '.php' );
            $object = $app->escape( $args[ 'object' ] );
            if (! $object ) $object = ucfirst( $model );
            $_entry = new $object;
            $table = $_entry->_table;
            $column = $app->escape( $args[ 'column' ] );
            $prefix = str_replace( 'mt_', '', $table );
            $column = "${prefix}_${column}";
            $ctx->stash( '_col_name', $column );
            $sql = "SELECT COUNT(*) AS cnt, ${column} FROM ${table} ";
            $not_null = $args[ 'not_null' ];
            $where = 'WHERE ';
            if ( $not_null ) {
                $where .= "(${column} != '') AND ";
            }
            if ( $_entry->has_column( $prefix . '_status' ) ) {
                $where .= "(${prefix}_status = '2') AND ";
            }
            if ( $_entry->has_column( $prefix . '_class' ) ) {
                $where .= "(${prefix}_class = '${model}') AND ";
            }
            $include_blogs = $app->include_exclude_blogs( $ctx, $args );
            if (! $include_blogs ) $ctx->error( '' );
            $ctx->stash( 'include_blogs', $include_blogs );
            $where .= "(${prefix}_blog_id ${include_blogs}) GROUP BY ${column}";
            $res = $ctx->mt->db()->Execute( $sql . $where );
            if ( $res->_numOfRows > 0 ) {
                $ctx->stash( '_group_count', $res->_numOfRows );
                if ( isset( $args[ 'lastn' ] ) ) {
                    $ctx->stash( '_group_count', $args[ 'lastn' ] );
                }
                $result = $res->GetArray();
                $direction = $args[ 'sort_order' ];
                $sort_by = $args[ 'sort_by' ];
                if ( (! $sort_by ) || ( $sort_by == 'count' ) ) {
                    $sort_by = 'cnt';
                } else {
                    $sort_by = $column;
                }
                if (! $direction ) $direction = 'descend';
                foreach ( $result as $key => $value ) {
                  $key_id[ $key ] = $value[ $sort_by ];
                }
                if ( $direction == 'ascend' ) {
                    array_multisort ( $key_id , SORT_ASC , $result );
                } else {
                    array_multisort ( $key_id , SORT_DESC , $result );
                }
                $ctx->stash( 'rows', $result );
            }
            $counter = 0;
        } else {
            $counter = $ctx->stash( '_group_counter' );
        }
        $_col_name = $ctx->stash( '_col_name' );
        $max = $ctx->stash( '_group_count' );
        $rows = $ctx->stash( 'rows' );
        if ( isset( $args[ 'glue' ] ) ) {
            $glue = $args[ 'glue' ];
        }
        if ( $counter < $max ) {
            $row = $rows[ $counter ];
            $ctx->__stash[ 'vars' ][ '__group_count__' ] = $row[ 'cnt' ];
            $ctx->__stash[ 'vars' ][ '__group_value__' ] = $row[ $_col_name ];
            $ctx->__stash[ 'vars' ][ '__counter__' ] = $counter + 1;
            $ctx->__stash[ 'vars' ][ '__odd__' ]     = ( $counter % 2 ) == 1;
            $ctx->__stash[ 'vars' ][ '__even__' ]    = ( $counter % 2 ) == 0;
            $ctx->__stash[ 'vars' ][ '__first__' ]   = $counter == 0;
            $ctx->__stash[ 'vars' ][ '__last__' ]    = ( $counter == $max );
            if ( $glue && ( $counter != $max ) ) {
                $content .= $glue;
            }
            $counter++;
            $ctx->stash( '_group_counter', $counter );
            $repeat = TRUE;
        } else {
            $ctx->restore( $localvars );
            $repeat = FALSE;
        }
        return $content;
    }

    function _hdlr_countgroupcount ( $args, &$ctx ) {
        return $ctx->__stash[ 'vars' ][ '__group_count__' ];
    }

    function _hdlr_countgroupvalue ( $args, &$ctx ) {
        return $ctx->__stash[ 'vars' ][ '__group_value__' ];
    }

    function _hdlr_copyfileto ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        $from = $args[ 'from' ];
        $to = $args[ 'to' ];
        $relative = $app->config( 'PathToRelative' );
        $blog = $ctx->stash( 'blog' );
        if ( $relative && isset( $blog ) ) {
            $from = $this->_get_relative( $blog, $from );
            $to = $this->_get_relative( $blog, $to );
        }
        if (! $this->_can_access_to( $ctx, $to ) ) {
            if ( isset( $args[ 'need_result' ] ) ) {
                $ctx->error( $app->translate( 'Cannot write to [_1].', $to ) );
            } else {
                $app->log( $app->translate( 'Cannot write to [_1].', $to ) );
                return '';
            }
        }
        if ( $from && (! $this->_can_access_to( $ctx, $from, TRUE ) ) ) {
            if ( isset( $args[ 'need_result' ] ) ) {
                $ctx->error( $app->translate( 'Cannot access [_1].', $from ) );
            } else {
                $app->log( $app->translate( 'Cannot access [_1].', $from ) );
                return '';
            }
        }
        $res = '';
        if ( isset( $args[ 'move' ] ) ) {
            if ( is_dir( $from ) ) {
                $res = $this->_dir_copy( $from, $to, TRUE );
            } else {
                $res = rename( $from, $to );
            }
        } elseif ( isset( $args[ 'remove' ] ) ) {
            if ( is_dir( $to ) ) {
                $res = $this->_remove_directory( $to );
            } else {
                $res = unlink( $to );
            }
        } else {
            if ( is_dir( $from ) ) {
                $res = $this->_dir_copy( $from, $to, FALSE );
            } else {
                $res = copy( $from, $to );
            }
        }
        if ( isset( $args[ 'need_result' ] ) ) {
            return $res;
        }
        return '';
    }

    function _hdlr_removefile( $args, &$ctx ) {
        $to = $args[ 'path' ];
        if (! $to ) $to = $args[ 'file' ];
        if (! $to ) {
            return '';
        }
        $args[ 'to' ] = $to;
        $args[ 'remove' ] = 1;
        return $this->_hdlr_copyfileto( $args, $ctx );
    }

    function _hdlr_movefileto ( $args, $ctx ) {
        $args[ 'move' ] = 1;
        return $this->_hdlr_copyfileto( $args, $ctx );
    }

    function _hdlr_readfromfile ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        $from = $args[ 'from' ];
        if (! $from ) $from = $args[ 'file' ];
        $relative = $app->config( 'PathToRelative' );
        $blog = $ctx->stash( 'blog' );
        if ( $relative && isset( $blog ) ) {
            $from = $this->_get_relative( $blog, $from );
        }
        if (! $this->_can_access_to( $ctx, $from, TRUE ) ) {
            if ( isset( $args[ 'need_result' ] ) ) {
                $ctx->error( $app->translate( 'Cannot read from [_1].', $from ) );
            } else {
                $app->log( $app->translate( 'Cannot read from [_1].', $from ) );
                return '';
            }
        }
        if ( file_exists( $from ) ) {
            return file_get_contents( $from );
        }
        return '';
    }

    function _hdlr_writetofile ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        $to = $args[ 'to' ];
        if (! $to ) $to = $args[ 'file' ];
        $relative = $app->config( 'PathToRelative' );
        $blog = $ctx->stash( 'blog' );
        if ( $relative && isset( $blog ) ) {
            $to = $this->_get_relative( $blog, $to );
        }
        if (! $this->_can_access_to( $ctx, $to ) ) {
            if ( isset( $args[ 'need_result' ] ) ) {
                $ctx->error( $app->translate( 'Cannot write to [_1].', $to ) );
            } else {
                $app->log( $app->translate( 'Cannot write to [_1].', $to ) );
                return '';
            }
        }
        $value = $args[ 'value' ];
        if (! $value ) $value = $args[ 'content' ];
        if ( isset( $args[ 'append' ] ) ) {
            $glue = '';
            if ( isset( $args[ 'glue' ] ) ) {
                $glue = $args[ 'glue' ];
            }
            if (! ( $fh = fopen( $to, 'a' ) ) ) {
                if ( isset( $args[ 'need_result' ] ) ) {
                    $ctx->error( $app->translate( 'Cannot write to [_1].', $to ) );
                } else {
                    $app->log( $app->translate( 'Cannot write to [_1].', $to ) );
                    return '';
                }
            }
            $res = fwrite( $fh, $value . $glue );
            fclose( $fh );
        } else {
            $res = file_put_contents( $to, $value );
        }
        if ( isset( $args[ 'need_result' ] ) ) {
            return $res;
        }
        return '';
    }

    function _get_relative ( $blog, $path ) {
        $blog_path = $blog->site_path();
        if ( preg_match( '/^\//', $path ) || preg_match( '/^\\\/', $path ) ) {
            $blog_path = preg_replace( '/\/$/', '', $blog_path );
            $blog_path = preg_replace( '/\\$/', '', $blog_path );
        }
        $path = $blog_path . DIRECTORY_SEPARATOR . $path;
        return $path;
    }

    function _can_access_to ( $ctx, $to, $read = FALSE ) {
        if ( preg_match( '/\.\./', $to ) ) {
            return 0;
        }
        $app = $ctx->stash( 'bootstrapper' );
        $can_access_to;
        if ( $read ) {
            $can_access_to = $app->config( 'CanReadFrom' );
        } else {
            $can_access_to = $app->config( 'CanWriteTo' );
        }
        if ( $can_access_to ) {
            if ( strtolower( $can_access_to ) == 'any' ) {
                return 1;
            }
            $paths = explode( $can_access_to, ',' );
            foreach ( $paths as $p ) {
                $p = trim( $p );
                if ( strpos( $to, $p ) === 0 ) {
                    return 1;
                }
            }
        }
        require_once( 'MTUtil.php' );
        $support_directory_path = support_directory_path();
        if ( strpos( $to, $support_directory_path ) === 0 ) {
            return 1;
        }
        $tempdir = $app->config( 'TempDir' );
        if ( strpos( $to, $tempdir ) === 0 ) {
            return 1;
        }
        $importdir = $app->config( 'ImportPath' );
        if ( strpos( $to, $importdir ) === 0 ) {
            return 1;
        }
        $blog = $ctx->stash( 'blog' );
        if ( isset( $blog ) ) {
            $site_path = $blog->site_path();
            if ( strpos( $to, $site_path ) === 0 ) {
                return 1;
            }
        }
        return 0;
    }

    function _remove_directory( $dir ) {
        if ( $handle = opendir( "$dir" ) ) {
            while ( FALSE !== ( $item = readdir( $handle ) ) ) {
                if ( $item != "." && $item != ".." ) {
                    if ( is_dir( "$dir/$item" ) ) {
                        $this->_remove_directory( "$dir/$item" );
                    } else {
                        unlink( "$dir/$item" );
                    }
                }
            }
            closedir( $handle );
            rmdir( $dir );
        }
        return 1;
    }

    function _dir_copy( $from, $to, $move = FALSE ) {
        if (!is_dir( $to ) ) {
            mkdir( $to );
        }
        if ( is_dir( $from ) ) {
          if ( $dh = opendir( $from ) ) {
                while ( ( $file = readdir( $dh ) ) !== FALSE ) {
                    if ( $file == '.' || $file == '..' ) {
                        continue;
                    }
                    if ( is_dir( $from . DIRECTORY_SEPARATOR . $file ) ) {
                        $this->_dir_copy( $from . DIRECTORY_SEPARATOR . $file, $to . DIRECTORY_SEPARATOR . $file );
                    } else {
                        if ( $move ) {
                            rename( $dir_name . DIRECTORY_SEPARATOR . $file, $to . DIRECTORY_SEPARATOR . $file );
                        } else {
                            copy( $dir_name . DIRECTORY_SEPARATOR . $file, $to . DIRECTORY_SEPARATOR . $file );
                        }
                    }
                }
                closedir( $dh );
            }
        }
        return TRUE;
    }

    function _hdlr_setproperty_block ( $args, $content, &$ctx, &$repeat ) {
         if ( isset( $content ) ) {
            $app = $ctx->stash( 'bootstrapper' );
            $blog_id = $args[ 'blog_id' ];
            $args[ 'value' ] = $content;
            return $this->_hdlr_setproperty( $args, $ctx );
         }
    }

    function _hdlr_cacheproperty ( $args, &$content, &$ctx, &$repeat ) {
        if (! isset( $content ) ) {
            // TODO::No repeat this block if cached...
            // if ( isset( $args[ 'blog_id' ] ) ) {
            //     $blog_id = $args[ 'blog_id' ];
            // }
            // $name = $args[ 'name' ];
            // if (! $blog_id ) $blog_id = 0;
            // $value = $this->_hdlr_getproperty( $args, $ctx );
            // if ( $value ) {
            //     $ctx->stash( "developer_property:${blog_id}:${name}", $value );
            // }
        } else {
            $args[ 'value' ] = $content;
            $this->_hdlr_setproperty( $args, $ctx );
        }
        return $content;
    }

    function _hdlr_if_property ( $args, $content, &$ctx, &$repeat ) {
        $name = $args[ 'name' ];
        $value = $this->_hdlr_getproperty( $args, $ctx );
        $ctx->__stash[ 'vars' ][ strtolower( $name ) ] = $value;
        $args[ 'name' ] = $name;
        require_once( 'block.mtif.php' );
        return smarty_block_mtif( $args, $content, $ctx, $repeat );
    }

    function _hdlr_if_request_method ( $args, $content, &$ctx, &$repeat ) {
        $value = $_SERVER[ 'REQUEST_METHOD' ];
        $ctx->__stash[ 'vars' ][ 'request_method' ] = $value;
        $args[ 'name' ] = 'request_method';
        require_once( 'block.mtif.php' );
        return smarty_block_mtif( $args, $content, $ctx, $repeat );
    }

    function _hdlr_if_validate_magic ( $args, $content, &$ctx, &$repeat ) {
        $app = $ctx->stash( 'bootstrapper' );
        if ( $app->validate_magic() ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
        }
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
    }

    function _hdlr_if_validtoken ( $args, $content, &$ctx, &$repeat ) {
        $app = $ctx->stash( 'bootstrapper' );
        if ( isset( $args[ 'name' ] ) ) {
            $sess_name = $args[ 'name' ];
            if (! $sess_name ) {
                $sess_name = 'magic_token';
            }
        }
        if ( isset( $args[ 'value' ] ) ) {
            $session_id = $args[ 'value' ];
        } else {
            $session_id = $app->param( $sess_name );
        }
        if (! $session_id ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        }
        require_once( 'class.mt_session.php' );
        $session = new Session;
        $session->Load( "session_id='${session_id}'" );
        if ( $session ) {
            $ttl = $app->config( 'OnetimeTokenTTL' );
            if ( ( time() - $session->session_start ) > $ttl ) {
                $session->Delete();
                return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
            } else {
                $session->Delete();
                return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
            }
        }
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
    }

    function _hdlr_get_onetimetoken ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        require_once( 'class.mt_session.php' );
        $session = new Session;
        $sessid = $app->make_magic_token();
        $terms = array ( 'id'    => $sessid,
                         'kind'  => 'DT',
                        );
        $session->set_values( $terms );
        $session->start = time();
        $session->Save();
        return $sessid;
    }

    function _hdlr_if_usercan ( $args, $content, &$ctx, &$repeat ) {
        $app = $ctx->stash( 'bootstrapper' );
        $author_id = $args[ 'author_id' ];
        if (! $author_id ) {
            $author = $app->user();
            if (! $author ) return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
            $author_id = $author->id;
        }
        if ( isset( $args[ 'include_superuser' ] ) ) {
            if ( $this->_is_superuser( $author_id ) ) {
                return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
            }
        }
        if (! $author_id ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        }
        $blog = $ctx->stash( 'blog' );
        $blog_id = $args[ 'blog_id' ];
        if (! $blog_id ) {
            $blog = $ctx->stash( 'blog' );
            if ( $blog ) $blog_id = $blog->id;
        }
        if (! $blog_id ) return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        require_once( 'class.mt_permission.php' );
        $Permission = new Permission;
        $where = "permission_author_id = '${author_id}'"
               . " and "
               . " permission_blog_id = '${blog_id}'";
        $results = $Permission->Find( $where );
        if ( empty( $results ) ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        }
        $perms = $results[ 0 ];
        $perms = $perms->permissions;
        $permission = $args[ 'permission' ];
        if (! $permission ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        }
        if ( strpos( $perms, "'${permission}'" ) !== FALSE ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
        }
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
    }

    function _hdlr_if_userrole ( $args, $content, &$ctx, &$repeat ) {
        $app = $ctx->stash( 'bootstrapper' );
        $author_id = $args[ 'author_id' ];
        if (! $author_id ) {
            $author = $app->user();
            if (! $author ) return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
            $author_id = $author->id;
        }
        // TODO::MTA(by Group)
        if (! $author_id ) return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        if ( $args[ 'include_superuser' ] ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, $this->_is_superuser( $author_id ) );
        }
        $blog_id = $args[ 'blog_id' ];
        if (! $blog_id ) {
            $blog = $ctx->stash( 'blog' );
            if ( $blog ) $blog_id = $blog->id;
        }
        if (! $blog_id ) return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        $role_name = $args[ 'role' ];
        if (! $role_name ) return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        require_once( 'class.mt_role.php' );
        $role = new Role;
        $results = $role->Find( "role_name = '${role_name}'" );
        if (! $results ) return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        $role = $results[ 0 ];
        $role_id = $role->id;
        require_once( 'class.mt_association.php' );
        $assoc = new Association;
        $results = $assoc->Find( "association_role_id = ${role_id} AND
                                  association_blog_id = ${blog_id} AND
                                  association_author_id = ${author_id}" );
        if (isset( $results ) ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
        }
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
    }

    function _is_superuser ( $author_id ) {
        require_once( 'class.mt_permission.php' );
        $Permission = new Permission;
        $where = "permission_author_id = '${author_id}'"
               . " and "
               . " permission_blog_id = 0";
        $results = $Permission->Find( $where );
        if (! isset( $results ) ) {
            return FALSE;
        }
        $perms = $results[ 0 ];
        $perms = $perms->permissions;
        if ( strpos( $perms, "'administer'" ) !== FALSE ) {
            return TRUE;
        }
        return FALSE;
    }

    function _hdlr_if_regexmatch ( $args, $content, &$ctx, &$repeat ) {
        $search = $args[ 'regex' ];
        $name = $args[ 'name' ];
        $string = $ctx->__stash[ 'vars' ][ strtolower( $name ) ];
        if ( preg_match( '!([a-zA-Z\s]+)$!s', $search, $match ) && ( preg_match( '/[eg]/', $match[ 1 ] ) ) ) {
            $search = substr( $search, 0, - strlen( $match[ 1 ] ) ) . preg_replace('![eg\s]+!', '', $match[ 1 ] );
        }
        if ( preg_match( $search, $string ) ) {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
        } else {
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
        }
    }

    function _hdlr_setproperty ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        $name = $args[ 'name' ];
        $name = $ctx->mt->db()->escape( $name );
        $value = $args[ 'value' ];
        // $value = $ctx->mt->db()->escape( $value );
        if ( isset( $args[ 'blog_id' ] ) ) {
            $blog_id = $args[ 'blog_id' ];
            $blog_id = $ctx->mt->db()->escape( $blog_id );
        }
        if (! $blog_id ) $blog_id = 0;
        require_once( 'class.mt_property.php' );
        $_prop = new Property;
        $prop = $_prop->Find( "property_blog_id=${blog_id} AND property_name='${name}'" );
        $ctx->stash( "developer_property:${blog_id}:${name}", $value );
        if ( isset( $args[ 'update' ] ) ) {
            $update = $args[ 'update' ];
        } elseif ( isset( $args[ 'force' ] ) ) {
            $update = $args[ 'force' ];
        }
        if ( is_array( $prop ) ) {
            $prop = $prop[ 0 ];
            if ( ( $prop->property_text != $value ) || $update ) {
                $prop->property_text = $value;
                $prop->start = time();
                $prop->Update();
            }
        } else {
            $prop = new Property;
            $prop->property_text = $value;
            $prop->property_blog_id = $blog_id;
            $prop->property_name = $name;
            $prop->start = time();
            $prop->Save();
        }
        return '';
        // $component = $app->component( 'Developer' );
        // if ( $blog_id ) {
        //     $plugindata = $component->get_config_value( 'developer_property', 'blog:' . $blog_id );
        // } else {
        //     $plugindata = $component->get_config_value( 'developer_property' );
        // }
        // if ( $plugindata ) {
        //     $data = json_decode( $plugindata, TRUE );
        // } else {
        //     $data = array();
        // }
        // $data[ $name ] = $value;
        // $data = json_encode( $data );
        // // plugin_config:configuration:developer
        // $get_from = 'configuration';
        // if ( $blog_id ) {
        //     $component->set_config_value( 'developer_property', $data, 'blog:' . $blog_id );
        //     $get_from .= ":blog:$blog_id";
        // } else {
        //     $component->set_config_value( 'developer_property', $data );
        // }
        // $component->stash( "plugin_config:${get_from}:developer", '' );
        // $app->stash( "plugin_config:${get_from}:developer", '' );
    }

    function _hdlr_getproperty ( $args, &$ctx ) {
        $value = $ctx->stash( "developer_property:${blog_id}:${name}" );
        if ( $value ) return $value;
        $app = $ctx->stash( 'bootstrapper' );
        $name = $args[ 'name' ];
        $name = $ctx->mt->db()->escape( $name );
        if ( isset( $args[ 'blog_id' ] ) ) {
            $blog_id = $args[ 'blog_id' ];
            $blog_id = $ctx->mt->db()->escape( $blog_id );
        }
        if (! $blog_id ) $blog_id = 0;
        require_once( 'class.mt_property.php' );
        $_prop = new Property;
        $prop = $_prop->Find( "property_blog_id=${blog_id} AND property_name='${name}'" );
        if ( is_array( $prop ) ) {
            $prop = $prop[ 0 ];
            if ( isset( $args[ 'ttl' ] ) ) {
                $ttl = $args[ 'ttl' ];
            } elseif ( isset( $args[ 'expired' ] ) ) {
                $ttl = $args[ 'expired' ];
            }
            if ( $ttl ) {
                $start = $prop->start;
                if ( ( time - $start ) > $ttl ) {
                    return '';
                }
            }
            $value = $prop->property_text;
            $ctx->stash( "developer_property:${blog_id}:${name}", $value );
            return $value;
        }
        return '';
    }

    function _hdlr_request_method ( $args, &$ctx ) {
        if ( isset( $_SERVER[ 'REQUEST_METHOD' ] ) ) {
            return $_SERVER[ 'REQUEST_METHOD' ];
        }
        return '';
    }

    function _hdlr_deleteproperty ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        if ( isset( $args[ 'name' ] ) ) {
            $name = $args[ 'name' ];
            $name = $ctx->mt->db()->escape( $name );
        }
        if ( isset( $args[ 'blog_id' ] ) ) {
            $blog_id = $args[ 'blog_id' ];
        }
        if (! $blog_id ) $blog_id = 0;
        if ( $name ) {
            require_once( 'class.mt_property.php' );
            $_prop = new Property;
            $prop = $_prop->Find( "property_blog_id=${blog_id} AND property_name='${name}'" );
            if ( is_array( $prop ) ) {
                $prop = $prop[ 0 ];
                $prop->Delete();
            }
        } else {
            if ( $blog_id ) {
                $sql = "DELETE FROM mt_property WHERE property_blog_id=${blog_id}";
            } else {
                $sql = 'TRUNCATE TABLE mt_property';
            }
            $ctx->mt->db()->execute( $sql );
        }
        return '';
        // $blog_id = $args[ 'blog_id' ];
        // $component = $app->component( 'Developer' );
        // if ( $blog_id ) {
        //     $plugindata = $component->get_config_value( 'developer_property', 'blog:' . $blog_id );
        // } else {
        //     $plugindata = $component->get_config_value( 'developer_property' );
        // }
        // if ( $plugindata ) {
        //     if (! $name ) {
        //         if ( $blog_id ) {
        //             $component->set_config_value( 'developer_property', NULL, 'blog:' . $blog_id );
        //         } else {
        //             $component->set_config_value( 'developer_property', NULL );
        //         }
        //         return;
        //     }
        //     $data = json_decode( $plugindata, TRUE );
        //     if ( array_key_exists( $name, $data ) ) {
        //         unset( $data[ $name ] );
        //         $get_from = 'configuration';
        //         if ( $blog_id ) {
        //             $component->set_config_value( 'developer_property', $data, 'blog:' . $blog_id );
        //             $get_from .= ":blog:$blog_id";
        //         } else {
        //             $plugindata = $component->get_config_value( 'developer_property', $data );
        //         }
        //         $component->stash( "plugin_config:${get_from}:developer", '' );
        //         $app->stash( "plugin_config:${get_from}:developer", '' );
        //     }
        // }
    }

    function _hdlr_magic_token ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        $token = $app->current_magic();
        if ( isset( $token ) ) {
            if ( $token ) return $token;
        }
        return '';
    }

    function _hdlr_phpscript ( $args, $content, &$ctx, &$repeat ) {
        $app = $ctx->stash( 'bootstrapper' );
        if (! $app->config( 'AllowPHPScript' ) ) {
            $ctx->error( $app->translate( 'Please set the environment variable AllowPHPScript.' ) );
        }
        if ( $content ) {
            ob_start();
            eval( $content );
            $content = ob_get_contents();
            ob_end_clean();
            $print = $args[ 'print' ];
            if (! $print ) $print = $args[ 'echo' ];
            if ( $print ) {
                return $content;
            }
            return '';
        }
    }

    function _hdlr_speedmeter ( $args, $content, &$ctx, &$repeat ) {
        $localvars = array( 'speedmeter_id' );
        if (! isset( $content ) ) {
            $ctx->localize( $localvars );
            $key = md5( uniqid( rand(), 1 ) . $name );
            $ctx->stash( 'speedmeter_id', $key );
            $ctx->stash( $key, microtime( TRUE ) );
        } else {
            $app = $ctx->stash( 'bootstrapper' );
            $scope = strtolower( $app->config( 'SpeedMeterDebugScope' ) );
            if ( (! $scope ) || ( $scope && $scope == 'none' ) ) {
                $repeat = FALSE;
                return $content;
            }
            $name = $args[ 'name' ];
            $repeat = FALSE;
            $key = $ctx->stash( 'speedmeter_id' );
            $start = $ctx->stash( $key );
            $end = microtime( TRUE );
            $ctx->restore( $localvars );
            $time = $end - $start;
            $message = $app->translate( 'The template for [_1] have been build.', "'{$name}'" );
            $message .= $app->translate( 'Publish time: [_1].', $time );
            if ( $scope == 'log' ) {
                $app->log( $message );
            } elseif ( $scope == 'screen' ) {
                $prefix = $args[ 'prefix' ] || '';
                $suffix = $args[ 'suffix' ] || '';
                $content .= $prefix . $message . $suffix;
            }
            return $content;
        }
    }

    function _hdlr_sendmail ( $args, &$ctx ) {
        $app = $ctx->stash( 'bootstrapper' );
        $to = $args[ 'to' ];
        $from = $args[ 'from' ];
        if (! $to ) $to = $app->config( 'EmailAddressMain' );
        if (! $from ) $from = $app->config( 'EmailAddressMain' );
        $subject = mb_encode_mimeheader( $args[ 'subject' ] );
        $body = $args[ 'body' ];
        $body = mb_convert_encoding( $body, 'ISO-2022-JP', 'UTF-8' );
        $headers = array( 'To' => $to, 'From' => $from, 'Subject' => $subject );
        $options = $args[ 'options' ];
        if ( $options ) {
            foreach ( $options as $key => $value ) {
                if ( $key == 'Subject' ) {
                    $headers[ $key ] = mb_encode_mimeheader( $value );
                } else {
                    $headers[ $key ] = $value;
                }
            }
        }
        if ( $pear = $app->config( 'PHPPearDir' ) ) {
            set_include_path( get_include_path() . PATH_SEPARATOR . $pear );
        }
        $plugin = $app->component( 'Developer' );
        $path = $plugin->plugin_path . DIRECTORY_SEPARATOR . 'php' . DIRECTORY_SEPARATOR . 'extlib';
        $path .= DIRECTORY_SEPARATOR . 'pear' . DIRECTORY_SEPARATOR;
        require_once( $path .'Mail.php' );
        $res = $this->send_mail( $app, $headers, $body );
        $need_result = $args[ 'need_result' ];
        if ( $need_result ) {
            return $res;
        }
        return '';
    }

    function send_mail ( $app, $headers, $body ) {
        $transfer = $app->config( 'MailTransfer' );
        if (! $transfer ) {
            $transfer = 'sendmail';
        }
        $transfer = strtolower( $transfer );
        if ( $transfer == 'sendmail' ) {
            $mail = Mail::factory( 'sendmail' );
        } else {
            $host = $app->config( 'SMTPServer' ) || 'localhost';
            $port = $app->config( 'SMTPPort' ) || 25;
            $auth = FALSE;
            if ( $app->config( 'SMTPAuth' ) ) {
                $auth = TRUE;
            }
            if ( $app->config( 'SMTPUser' ) ) {
                $user = $app->config( 'SMTPUser' );
            }
            if ( $app->config( 'SMTPPassword' ) ) {
                $passwd = $app->config( 'SMTPPassword' );
            }
            $params = array(
                'host' => SMTPServer,
                'port' => $port,
                'auth' => $auth,
            );
            if ( $user ) {
                $params[ 'username' ] = $user;
                $params[ 'password' ] = $passwd;
            }
            $mail = Mail::factory( 'smtp', $params );
        }
        $recipients = $headers[ 'To' ];
        return $mail->send( $recipients, $headers, $body );
    }

    function _hdlr_build ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtbuild.php' );
        return smarty_block_mtbuild( $args, $content, $ctx, $repeat );
    }

    function _hdlr_clearcontext ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtclearcontext.php' );
        return smarty_block_mtclearcontext( $args, $content, $ctx, $repeat );
    }

    function _hdlr_csscompressor ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtcsscompressor.php' );
        return smarty_block_mtcsscompressor( $args, $content, $ctx, $repeat );
    }

    function _hdlr_fileinfo ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtfileinfo.php' );
        return smarty_block_mtfileinfo( $args, $content, $ctx, $repeat );
    }

    function _hdlr_fileinfoloop ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtfileinfoloop.php' );
        return smarty_block_mtfileinfoloop( $args, $content, $ctx, $repeat );
    }

    function _hdlr_htmlcompressor ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mthtmlcompressor.php' );
        return smarty_block_mthtmlcompressor( $args, $content, $ctx, $repeat );
    }

    function _hdlr_if_cookie ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtifcookie.php' );
        return smarty_block_mtifcookie( $args, $content, $ctx, $repeat );
    }

    function _hdlr_if_entryisincategory ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtifentryisincategory.php' );
        return smarty_block_mtifentryisincategory( $args, $content, $ctx, $repeat );
    }

    function _hdlr_if_header ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtifheader.php' );
        return smarty_block_mtifheader( $args, $content, $ctx, $repeat );
    }

    function _hdlr_if_language ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtiflanguage.php' );
        return smarty_block_mtiflanguage( $args, $content, $ctx, $repeat );
    }

    function _hdlr_if_theurlfound ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtiftheurlfound.php' );
        return smarty_block_mtiftheurlfound( $args, $content, $ctx, $repeat );
    }

    function _hdlr_jscompressor ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtjscompressor.php' );
        return smarty_block_mtjscompressor( $args, $content, $ctx, $repeat );
    }

    // function _hdlr_json2mtml ( $args, $content, &$ctx, &$repeat ) {
    //     require_once( $this->tags_dir() . 'block.mtjson2mtml.php' );
    //     return smarty_block_mtjson2mtml( $args, $content, $ctx, $repeat );
    // }

    function _hdlr_setcontext ( $args, $content, &$ctx, &$repeat ) {
        require_once( $this->tags_dir() . 'block.mtsetcontext.php' );
        return smarty_block_mtsetcontext( $args, $content, $ctx, $repeat );
    }

    // function _hdlr_varsrecurse ( $args, $content, &$ctx, &$repeat ) {
    //     require_once( $this->tags_dir() . 'block.mtvarsrecurse.php' );
    //     return smarty_block_mtvarsrecurse( $args, $content, $ctx, $repeat );
    // }

    function _hdlr_assetthumbnailfile ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtassetthumbnailfile.php' );
        return smarty_function_mtassetthumbnailfile( $args, $ctx );
    }

    function _hdlr_buildlink ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtbuildlink.php' );
        return smarty_function_mtbuildlink( $args, $ctx );
    }

    function _hdlr_clearcookie ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtclearcookie.php' );
        return smarty_function_mtclearcookie( $args, $ctx );
    }

    function _hdlr_cookiedump ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtcookiedump.php' );
        return smarty_function_mtcookiedump( $args, $ctx );
    }

    function _hdlr_envdump ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtenvdump.php' );
        return smarty_function_mtenvdump( $args, $ctx );
    }
//Start not export
    function _hdlr_developerscript ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtdeveloperscript.php' );
        return smarty_function_mtdeveloperscript( $args, $ctx );
    }
//End not export

    function _hdlr_getcookie ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtgetcookie.php' );
        return smarty_function_mtgetcookie( $args, $ctx );
    }

    function _hdlr_getenv ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtgetenv.php' );
        return smarty_function_mtgetenv( $args, $ctx );
    }

    function _hdlr_getepoc ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtgetepoc.php' );
        return smarty_function_mtgetepoc( $args, $ctx );
    }

    function _hdlr_getheader ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtgetheader.php' );
        return smarty_function_mtgetheader( $args, $ctx );
    }

    function _hdlr_geturlmtime ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtgeturlmtime.php' );
        return smarty_function_mtgeturlmtime( $args, $ctx );
    }

    function _hdlr_log ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtlog.php' );
        return smarty_function_mtlog( $args, $ctx );
    }

    function _hdlr_mljob ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtmljob.php' );
        return smarty_function_mtmljob( $args, $ctx );
    }

    function _hdlr_mljobtitle ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtmljobtitle.php' );
        return smarty_function_mtmljobtitle( $args, $ctx );
    }

    function _hdlr_query2log ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtquery2log.php' );
        return smarty_function_mtquery2log( $args, $ctx );
    }

    function _hdlr_querydump ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtquerydump.php' );
        return smarty_function_mtquerydump( $args, $ctx );
    }

    function _hdlr_setcolumns2vars ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtsetcolumns2vars.php' );
        return smarty_function_mtsetcolumns2vars( $args, $ctx );
    }

    function _hdlr_setcookie ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtsetcookie.php' );
        return smarty_function_mtsetcookie( $args, $ctx );
    }

    function _hdlr_setfields2vars ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtsetfields2vars.php' );
        return smarty_function_mtsetfields2vars( $args, $ctx );
    }

    function _hdlr_throwsql ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtthrowsql.php' );
        return smarty_function_mtthrowsql( $args, $ctx );
    }

    function _hdlr_translate ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mttranslate.php' );
        return smarty_function_mttranslate( $args, $ctx );
    }

    function _hdlr_vardump ( $args, &$ctx ) {
        require_once( $this->tags_dir() . 'function.mtvardump.php' );
        return smarty_function_mtvardump( $args, $ctx );
    }

    function _filter_convert2base64 ( $text, $arg ) {
        require_once( $this->tags_dir() . 'modifier.convert2base64.php' );
        return smarty_modifier_convert2base64( $text, $arg );
    }

    function _filter_outiftheurlfound ( $text, $arg ) {
        require_once( $this->tags_dir() . 'modifier.outiftheurlfound.php' );
        return smarty_modifier_outiftheurlfound( $text, $arg );
    }

}

?>