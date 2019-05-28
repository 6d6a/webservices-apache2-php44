with import <nixpkgs> {};

with lib;

let

  locale = glibcLocales.override {
      allLocales = false;
      locales = ["en_US.UTF-8/UTF-8"];
  };

  postfix = stdenv.mkDerivation rec {
      name = "postfix-${version}";
      version = "3.4.5";
      srcs = [
         ( fetchurl {
            url = "ftp://ftp.cs.uu.nl/mirror/postfix/postfix-release/official/${name}.tar.gz";
            sha256 = "17riwr21i9p1h17wpagfiwkpx9bbx7dy4gpdl219a11akm7saawb";
          })
       ./patch/postfix/mj/lib
      ];
      nativeBuildInputs = [ makeWrapper m4 ];
      buildInputs = [ db openssl cyrus_sasl icu libnsl pcre ];
      sourceRoot = "postfix-3.4.5";
      hardeningDisable = [ "format" ];
      hardeningEnable = [ "pie" ];
      patches = [
       ./patch/postfix/nix/postfix-script-shell.patch
       ./patch/postfix/nix/postfix-3.0-no-warnings.patch
       ./patch/postfix/nix/post-install-script.patch
       ./patch/postfix/nix/relative-symlinks.patch
       ./patch/postfix/mj/sendmail.patch
       ./patch/postfix/mj/postdrop.patch
       ./patch/postfix/mj/globalmake.patch
      ];
       ccargs = lib.concatStringsSep " " ([
          "-DUSE_TLS"
          "-DHAS_DB_BYPASS_MAKEDEFS_CHECK"
          "-DNO_IPV6"
          "-DNO_KQUEUE" "-DNO_NIS" "-DNO_DEVPOLL" "-DNO_EAI" "-DNO_PCRE"
       ]);

       auxlibs = lib.concatStringsSep " " ([
           "-lresolv" "-lcrypto" "-lssl" "-ldb"
       ]);
      preBuild = ''
          cp -pr ../lib/* src/global
          sed -e '/^PATH=/d' -i postfix-install
          sed -e "s|@PACKAGE@|$out|" -i conf/post-install

          # post-install need skip permissions check/set on all symlinks following to /nix/store
          sed -e "s|@NIX_STORE@|$NIX_STORE|" -i conf/post-install

          export command_directory=$out/sbin
          export config_directory=/etc/postfix
          export meta_directory=$out/etc/postfix
          export daemon_directory=$out/libexec/postfix
          export data_directory=/var/lib/postfix
          export html_directory=$out/share/postfix/doc/html
          export mailq_path=$out/bin/mailq
          export manpage_directory=$out/share/man
          export newaliases_path=$out/bin/newaliases
          export queue_directory=/var/spool/postfix
          export readme_directory=$out/share/postfix/doc
          export sendmail_path=$out/bin/sendmail
          make makefiles CCARGS='${ccargs}' AUXLIBS='${auxlibs}'
      '';

      installTargets = [ "non-interactive-package" ];
      installFlags = [ "install_root=installdir" ];

      postInstall = ''
          mkdir -p $out
          cat << EOF > installdir/etc/postfix/main.cf
          mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
          mailbox_size_limit = 0
          recipient_delimiter = +
          message_size_limit = 20480000
          maillog_file = /dev/stdout
          relayhost = mail-checker2.intr
          EOF
          echo "smtp            25/tcp          mail" >> installdir/etc/services
          echo "postlog   unix-dgram n  -       n       -       1       postlogd" >> installdir/etc/postfix/master.cf
          echo "*: /dev/null" >> installdir/etc/aliases
          mv -v installdir/$out/* $out/
          cp -rv installdir/etc $out
          sed -e '/^PATH=/d' -i $out/libexec/postfix/post-install
          wrapProgram $out/libexec/postfix/post-install \
            --prefix PATH ":" ${lib.makeBinPath [ coreutils findutils gnugrep ]}
          wrapProgram $out/libexec/postfix/postfix-script \
            --prefix PATH ":" ${lib.makeBinPath [ coreutils findutils gnugrep gawk gnused ]}
          rm -f $out/libexec/postfix/post-install \
                $out/libexec/postfix/postfix-wrapper \
                $out/libexec/postfix/postfix-script \
                $out/libexec/postfix/.post-install-wrapped \
                $out/libexec/postfix/postfix-tls-script \
                $out/libexec/postfix/postmulti-script \
                $out/libexec/postfix/.postfix-script-wrapped
      '';
  };

  apacheHttpd = stdenv.mkDerivation rec {
      version = "2.4.39";
      name = "apache-httpd-${version}";
      src = fetchurl {
          url = "mirror://apache/httpd/httpd-${version}.tar.bz2";
          sha256 = "18ngvsjq65qxk3biggnkhkq8jlll9dsg9n3csra9p99sfw2rvjml";
      };
      outputs = [ "out" "dev" ];
      setOutputFlags = false; # it would move $out/modules, etc.
      buildInputs = [ perl zlib nss_ldap nss_pam_ldapd openldap];
      prePatch = ''
          sed -i config.layout -e "s|installbuilddir:.*|installbuilddir: $dev/share/build|"
      '';

      preConfigure = ''
          configureFlags="$configureFlags --includedir=$dev/include"
      '';

      configureFlags = [
          "--with-apr=${apr.dev}"
          "--with-apr-util=${aprutil.dev}"
          "--with-z=${zlib.dev}"
          "--with-pcre=${pcre.dev}"
          "--disable-maintainer-mode"
          "--disable-debugger-mode"
          "--enable-mods-shared=all"
          "--enable-mpms-shared=all"
          "--enable-cern-meta"
          "--enable-imagemap"
          "--enable-cgi"
          "--disable-ldap"
          "--with-mpm=prefork"
      ];

      enableParallelBuilding = true;
      stripDebugList = "lib modules bin";
      postInstall = ''
          #mkdir -p $doc/share/doc/httpd
          #mv $out/manual $doc/share/doc/httpd
          mkdir -p $dev/bin

          mv $out/bin/apxs $dev/bin/apxs
      '';

      passthru = {
          inherit apr aprutil ;
      };
  };

  phpioncubepack = stdenv.mkDerivation rec {
      name = "phpioncubepack";
      src =  fetchurl {
          url = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz";
          sha256 = "08bq06yr29zns53m603yv5h11ija8vzkq174qhcj4hz7ya05zb4a";
      };
      installPhase = ''
                  mkdir -p  $out/
                  tar zxvf  ${src} -C $out/ ioncube/ioncube_loader_lin_4.4.so
      '';
  };

  zendoptimizer = stdenv.mkDerivation rec {
      name = "zend-optimizer-3.3.9";
      src =  fetchurl {
          url = "http://downloads.zend.com/optimizer/3.3.9/ZendOptimizer-3.3.9-linux-glibc23-x86_64.tar.gz";
          sha256 = "1f7c7p9x9p2bjamci04vr732rja0l1279fvxix7pbxhw8zn2vi1d";
      };
      installPhase = ''
                  mkdir -p  $out/
                  tar zxvf  ${src} -C $out/ ZendOptimizer-3.3.9-linux-glibc23-x86_64/data/4_4_x_comp/ZendOptimizer.so
      '';
  };

  pcre831 = stdenv.mkDerivation rec {
      name = "pcre-8.31";
      src = fetchurl {
          url = "https://ftp.pcre.org/pub/pcre/${name}.tar.bz2";
          sha256 = "0g4c0z4h30v8g8qg02zcbv7n67j5kz0ri9cfhgkpwg276ljs0y2p";
      };
      outputs = [ "out" ];
      configureFlags = ''
          --enable-jit
      '';
  };

  libjpegv6b = stdenv.mkDerivation rec {
     name = "libjpeg-6b";
     src = fetchurl {
         url = "http://www.ijg.org/files/jpegsrc.v6b.tar.gz";
         sha256 = "0pg34z6rbkk5kvdz6wirf7g4mdqn5z8x97iaw17m15lr3qjfrhvm";
     };
     buildInputs = [ nasm libtool autoconf213 coreutils ];
     doCheck = true;
     checkTarget = "test";
     configureFlags = ''
          --enable-static
          --enable-shared
     '';
     preBuild = ''
          mkdir -p $out/lib
          mkdir -p $out/bin
          mkdir -p $out/man/man1
          mkdir -p $out/include
     '';
     preInstall = ''
          mkdir -p $out/lib
          mkdir -p $out/bin
          mkdir -p $out/man/man1
          mkdir -p $out/include
     '';
      patches = [
       ./patch/jpeg6b.patch
      ];
  };

  libpng12 = stdenv.mkDerivation rec {
     name = "libpng-1.2.59";
     src = fetchurl {
        url = "mirror://sourceforge/libpng/${name}.tar.xz";
        sha256 = "b4635f15b8adccc8ad0934eea485ef59cc4cae24d0f0300a9a941e51974ffcc7";
     };
     buildInputs = [ zlib ];
     doCheck = true;
     checkTarget = "test";
  };

  connectorc = stdenv.mkDerivation rec {
     name = "mariadb-connector-c-${version}";
     version = "6.1.0";

     src = fetchurl {
         url = "https://downloads.mysql.com/archives/get/file/mysql-connector-c-6.1.0-src.tar.gz";
         sha256 = "0cifddg0i8zm8p7cp13vsydlpcyv37mz070v6l2mnvy0k8cng2na";
         name   = "mariadb-connector-c-${version}-src.tar.gz";
     };

  # outputs = [ "dev" "out" ]; FIXME: cmake variables don't allow that < 3.0
     cmakeFlags = [
            "-DWITH_EXTERNAL_ZLIB=ON"
            "-DMYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock"
     ];

  # The cmake setup-hook uses $out/lib by default, this is not the case here.
     preConfigure = stdenv.lib.optionalString stdenv.isDarwin ''
             cmakeFlagsArray+=("-DCMAKE_INSTALL_NAME_DIR=$out/lib/mariadb")
     '';

     nativeBuildInputs = [ cmake ];
     propagatedBuildInputs = [ openssl zlib ];
     buildInputs = [ libiconv ];
     enableParallelBuilding = true;
  };

  php4 = stdenv.mkDerivation rec {
      name = "php-4.4.9";
      sha256 = "1hjn2sdm8sn8xsd1y5jlarx3ddimdvm56p1fxaj0ydm3dgah5i9a";
      enableParallelBuilding = true;
      nativeBuildInputs = [ pkgconfig autoconf213 ];
      hardeningDisable = [ "fortify" "stackprotector" "pie" "pic" "strictoverflow" "format" "relro" "bindnow" ];
      buildInputs = [
         autoconf213
         automake
         pkgconfig
         curl
         apacheHttpd.dev
         bison
         bzip2
         flex
         freetype
         gettext
         icu
         libzip
         libjpegv6b
         libmcrypt
         libmhash
         libpng12
         libxml2
         libsodium
         icu.dev
         xorg.libXpm.dev
         libxslt
         connectorc
         pam
         expat
         pcre831
         postgresql
         readline
         sqlite
         uwimap
         zlib
         libiconv
         t1lib
         libtidy
         kerberos
         openssl
         glibc.dev
         glibcLocales
         sablotron
      ];

      CXXFLAGS = "-std=c++11";

      configureFlags = ''
       --disable-maintainer-zts
       --disable-pthreads
       --disable-fpm
       --disable-cgi
       --disable-phpdbg
       --disable-debug
       --disable-memcached-sasl
       --enable-pdo
       --enable-dom
       --enable-inline-optimization
       --enable-dba
       --enable-bcmath
       --enable-soap
       --enable-sockets
       --enable-zip
       --enable-exif
       --enable-ftp
       --enable-mbstring=ru
       --enable-calendar
       --enable-timezonedb
       --enable-gd-native-ttf
       --enable-sysvsem
       --enable-sysvshm
       --enable-opcache
       --enable-wddx
       --enable-magic-quotes
       --enable-memory-limit
       --enable-local-infile
       --enable-force-cgi-redirect
       --enable-xslt
       --enable-dbase
       --with-iconv
       --with-dbase
       --with-xslt-sablot=${sablotron}
       --with-xslt
       --with-expat-dir=${expat}
       --with-kerberos
       --with-ttf
       --with-config-file-scan-dir=/etc/php.d
       --with-pcre-regex=${pcre831}
       --with-imap=${uwimap}
       --with-imap-ssl
       --with-mhash=${libmhash}
       --with-libzip
       --with-curl=${curl.dev}
       --with-curlwrappers
       --with-zlib=${zlib.dev}
       --with-readline=${readline.dev}
       --with-pdo-sqlite=${sqlite.dev}
       --with-pgsql=${postgresql}
       --with-pdo-pgsql=${postgresql}
       --with-gd
       --with-freetype-dir=${freetype.dev}
       --with-png-dir=${libpng12}
       --with-jpeg-dir=${libjpegv6b}
       --with-openssl
       --with-gettext=${glibc.dev}
       --with-xsl=${libxslt.dev}
       --with-mcrypt=${libmcrypt}
       --with-bz2=${bzip2.dev}
       --with-sodium=${libsodium.dev}
       --with-tidy=${html-tidy}
       --with-password-argon2=${libargon2}
       --with-apxs2=${apacheHttpd.dev}/bin/apxs
       --with-mysql=${connectorc}
       --with-dom=${libxml2.dev}
       --with-dom-xslt=${libxslt.dev}
       '';

#      hardeningDisable = [ "bindnow" ];

      preConfigure = ''
        cp -pr ../standard/* ext/standard
        # Don't record the configure flags since this causes unnecessary
        # runtime dependencies
        for i in main/build-defs.h.in scripts/php-config.in; do
          substituteInPlace $i \
            --replace '@CONFIGURE_COMMAND@' '(omitted)' \
            --replace '@CONFIGURE_OPTIONS@' "" \
            --replace '@PHP_LDFLAGS@' ""
        done

        [[ -z "$libxml2" ]] || addToSearchPath PATH $libxml2/bin

        export EXTENSION_DIR=$out/lib/php/extensions

        configureFlags+=(--with-config-file-path=$out/etc \
          --includedir=$dev/include)

        ./buildconf --force
      '';

      srcs = [ 
             ( fetchurl {
                 url = "https://museum.php.net/php4/php-4.4.9.tar.bz2";
                 inherit sha256;
             })
             ./src/ext/standard
      ];
      sourceRoot = "php-4.4.9";
      patches = [ 
                 ./patch/php4/mj/php4-apache24.patch
                 ./patch/php4/mj/php4-openssl.patch
                 ./patch/php4/mj/php4-domxml.patch
                 ./patch/php4/mj/php4-pcre.patch
                 ./patch/php4/mj/apxs.patch
      ];
      stripDebugList = "bin sbin lib modules";
      outputs = [ "out" ];
      doCheck = false;
      checkTarget = "test"; 
      postInstall = ''
          sed -i $out/include/php/main/build-defs.h -e '/PHP_INSTALL_IT/d'
      '';     
  };

#http://mpm-itk.sesse.net/
  apacheHttpdmpmITK = stdenv.mkDerivation rec {
      name = "apacheHttpdmpmITK";
      buildInputs =[ apacheHttpd.dev ];
      src = fetchurl {
          url = "http://mpm-itk.sesse.net/mpm-itk-2.4.7-04.tar.gz";
          sha256 = "609f83e8995416c5491348e07139f26046a579db20cf8488ebf75d314668efcf";
      };
      configureFlags = [ "--with-apxs2=${apacheHttpd.dev}/bin/apxs" ];
      patches = [ ./patch/httpd/itk.patch ];
      postInstall = ''
          mkdir -p $out/modules
          cp -pr /tmp/out/mpm_itk.so $out/modules
      '';
      outputs = [ "out" ];
      enableParallelBuilding = true;
      stripDebugList = "lib modules bin";
  };

  mjerrors = stdenv.mkDerivation rec {
      name = "mjerrors";
      buildInputs = [ gettext ];
      src = fetchGit {
              url = "git@gitlab.intr:shared/http_errors.git";
              ref = "master";
              rev = "f83136c7e6027cb28804172ff3582f635a8d2af7";
            };
      outputs = [ "out" ];
      postInstall = ''
             mkdir -p $out/tmp $out/mjstuff/mj_http_errors
             cp -pr /tmp/mj_http_errors/* $out/mjstuff/mj_http_errors/
      '';
  };

  rootfs = stdenv.mkDerivation rec {
      nativeBuildInputs = [ 
         mjerrors
         phpioncubepack
         php4
         bash
         apacheHttpd
         apacheHttpdmpmITK
         execline
         coreutils
         findutils
         postfix
         perl
         gnugrep
         zendoptimizer
      ];
      name = "rootfs";
      src = ./rootfs;
      buildPhase = ''
         echo $nativeBuildInputs
         export coreutils="${coreutils}"
         export bash="${bash}"
         export apacheHttpdmpmITK="${apacheHttpdmpmITK}"
         export apacheHttpd="${apacheHttpd}"
         export s6portableutils="${s6-portable-utils}"
         export phpioncubepack="${phpioncubepack}"
         export php4="${php4}"
         export zendoptimizer="${zendoptimizer}"
         export mjerrors="${mjerrors}"
         export postfix="${postfix}"
         export libstdcxx="${gcc-unwrapped.lib}"
         echo ${apacheHttpd}
         for file in $(find $src/ -type f)
         do
           echo $file
           substituteAllInPlace $file
         done
      '';
      installPhase = ''
         cp -pr ${src} $out/
      '';
  };

in 

pkgs.dockerTools.buildLayeredImage rec {
    name = "docker-registry.intr/webservices/php4";
    tag = "master";
    contents = [ php4 
                 perl
                 phpioncubepack
                 zendoptimizer
                 bash
                 coreutils
                 findutils
                 apacheHttpd.out
                 apacheHttpdmpmITK
                 rootfs
                 execline
                 tzdata
                 mime-types
                 postfix
                 locale
                 perl528Packages.Mojolicious
                 perl528Packages.base
                 perl528Packages.libxml_perl
                 perl528Packages.libnet
                 perl528Packages.libintl_perl
                 perl528Packages.LWP 
                 perl528Packages.ListMoreUtilsXS
                 perl528Packages.LWPProtocolHttps
                 mjerrors
                 glibc
                 gcc-unwrapped.lib
    ];
      extraCommands = ''
          chmod 555 ${postfix}/bin/postdrop
      '';
   config = {
       Entrypoint = [ "${apacheHttpd}/bin/httpd" "-D" "FOREGROUND" "-d" "${rootfs}/etc/httpd" ];
       Env = [ "TZ=Europe/Moscow" "TZDIR=/share/zoneinfo" "LOCALE_ARCHIVE_2_27=${locale}/lib/locale/locale-archive" "LC_ALL=en_US.UTF-8" "HTTPD_PORT=8074" "HTTPD_SERVERNAME=web15" ];
    };
}
