#!/usr/bin/env bash
#
# Copyright 2010-2012 Tasos Laskos <tasos.laskos@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Experimental Arachni install script, it's supposed to take care of everything
# including system library dependencies, Ruby, gem dependencies and Arachni itself.
#
# Requirements:
#   * wget -- To download the necessary packages
#   * build-essential -- For compilers (gcc & g++), headers etc.
#
# Install them with:
#   sudo apt-get install wget build-essential
#

cat<<EOF

             Arachni installer (experimental)
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

 It will download and install all dependencies, configure the environment
 and install Arachni itself.

     by Tasos Laskos <tasos.laskos@gmail.com>
-------------------------------------------------------------------------

EOF

if [[ "$1" == '-h' ]] || [[ "$1" == '--help' ]]; then
    cat <<EOF
Usage: $0 [installation directory]

Installation directory defaults to './arachni'.

If at any point you decide to cancel the process, re-running the script
will continue from the point it left off.

EOF
    exit
fi

echo
echo "# Checking for installation dependencies"
echo '----------------------------------------'
deps="
    wget
    gcc
    g++
"
for dep in $deps; do
    echo -n "  * $dep"
    if [[ ! `which "$dep"` ]]; then
        echo " -- FAIL"
        fail=true
    else
        echo " -- OK"
    fi
done

if [[ $fail ]]; then
    echo "Please install the missing dependencies and try again."
    exit 1
fi

arachni_tarball_url="https://github.com/Zapotek/arachni/tarball/experimental"

#
# All system library dependencies in proper order
#
libs=(
    http://zlib.net/zlib-1.2.6.tar.gz
    http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz
    http://www.openssl.org/source/openssl-0.9.8n.tar.gz
    http://www.sqlite.org/sqlite-autoconf-3071000.tar.gz
    ftp://xmlsoft.org/libxml2/libxml2-2.7.8.tar.gz
    ftp://xmlsoft.org/libxslt/libxslt-1.1.26.tar.gz
    http://curl.haxx.se/download/curl-7.24.0.tar.gz
    https://rvm.beginrescueend.com/src/yaml-0.1.4.tar.gz
    http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.3-p125.tar.gz
)

libs_so=(
    libz.so.1.2.6
    libiconv.so.2.5.1
    libssl.so.0.9.8
    libsqlite3.so.0.8.6
    libxml2.so.2.7.8
    libxslt.so.1.1.26
    libcurl.so.4.2.0
    libyaml-0.so.2.0.2
    ruby
)

if [[ ! -z "$1" ]]; then
    # root path
    root="$1"
else
    # root path
    root="arachni"
fi

root=`readlink -f $root`

# holds tarball archives
archives_path="$root/archives"

# holds exracted archives
src_path="$root/src"

# holds STDERR and STDOUT
logs_path="$root/logs"

# --prefix value for 'configure' scripts
configure_prefix="$root/usr"
usr_path=$configure_prefix

# PATH for our Ruby environment
bin_path="$root_path/bin:$usr_path/bin"

# Gem storage directories
gem_home="$root/gems"
gem_path=$gem_home

#
# Special config for packages that need something extra.
# These are called dynamically using the obvious naming convention.
#
# For some reason assoc arrays don't work...
#
configure_libxslt="./configure --with-libxml-prefix=$configure_prefix"

configure_ruby="./configure --with-opt-dir=$configure_prefix \
--with-libyaml-dir=$configure_prefix \
--with-zlib-dir=$configure_prefix \
--with-openssl-dir=$configure_prefix \
--disable-install-doc --enable-shared"

configure_openssl="./config -I$usr_path/include -L$usr_path/lib \
zlib no-asm no-krb5 shared"

configure_curl="./configure \
--with-ssl=$usr_path/ssl \
--with-zlib=$usr_path \
--enable-optimize --enable-nonblocking \
--enable-threaded-resolver --enable-crypto-auth --enable-cookies"

orig_path=$PATH

#
# Creates the directory structure for the env
#
setup_dirs( ) {

    echo -n "  * $root"
    #rm -rf $root
    if [[ ! -s $root ]]; then
        echo
        mkdir $root
    else
        echo " -- already exists."
    fi

    cd $root

    dirs="
        logs
        archives
        bin
        gems
        src
        usr/bin
        usr/include
        usr/info
        usr/lib
        usr/man
    "
    for dir in $dirs
    do
        echo -n "  * $root/$dir"
        if [[ ! -s $dir ]]; then
            echo
            mkdir -p $dir
        else
            echo " -- already exists."
        fi
    done

    cd - > /dev/null
}

#
# Checks the last return value and exits with an error msg on failure
#
handle_failure(){
    rc=$?
    if [[ $rc != 0 ]] ; then
        echo "Installation failed, check $logs_path/$1 for details."
        echo "When you resolve the issue you can run the script again to continue where the process left off."
        exit $rc
    fi
}

download() {

    echo -n "  * Downloading $1"
    echo -n " -  0% ETA:      -s"
    wget -c --progress=dot --no-check-certificate $1 $2 2>&1 | \
        while read line; do
            echo $line | grep "%" | sed -u -e "s/\.//g" | \
            awk '{printf("\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b%4s ETA: %6s", $2, $4)}'
        done

    echo -e "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b                           "
}

#
# Donwloads an archive (by url) and places it under $archives_path
#
download_archive() {
    cd $archives_path

    download $1
    handle_failure $2

    cd - > /dev/null
}

#
# Extracts an archive (by name) under $src_path
#
extract_archive() {
    echo "  * Extracting"
    tar xvf $archives_path/$1-*.tar.gz -C $src_path &>> $logs_path/$1
    handle_failure $1
}

#
# Installs a package from src by name
#
install_from_src() {
    cd $src_path/$1-*

    echo "  * Cleaning"
    make clean &>> $logs_path/$1

    eval special_config=\$$"configure_$1"
    if [[ $special_config ]]; then
        configure=$special_config
    else
        configure="./configure"
    fi

    configure="${configure} --prefix=$configure_prefix"

    echo "  * Configuring ($configure)"
    echo "Configuring with: $configure" &>> $logs_path/$1

    $configure &>> $logs_path/$1
    handle_failure $1

    echo "  * Compilling"
    make &>> $logs_path/$1
    handle_failure $1

    echo "  * Installing"
    make install &>> $logs_path/$1
    handle_failure $1

    cd - > /dev/null
}

get_name(){
    first_pass=`expr match "$1" '.*\/\(.*\)-'`
    name=`expr "$first_pass" : '\(.*\)-'`

    [[ ! $name ]] && name=$first_pass
    echo $name
}

#
# Downloads and install a package by URL
#
download_and_install() {
    name=`get_name $1`

    #if [[ ! -s `echo $archives_path/$name*` ]]; then
        download_archive $1 $name
    #else
        #    echo "  * Already downloaded"
    #fi

    #if [[ ! -s `echo $src_path/$name*` ]]; then
        extract_archive $name
    #else
        #    echo "  * Already extracted"
    #fi

    install_from_src $name
    echo
}

#
# Downloads and installs all $libs
#
install_libs() {
    libtotal=${#libs[@]}

    for (( i=0; i<$libtotal; i++ )); do
        so=${libs_so[$i]}
        lib=${libs[$i]}
        idx=`expr $i + 1`

        echo "## ($idx/$libtotal) `get_name $lib`"

        so_files="$usr_path/lib/$so"
        if [[ -s $so_files ]]; then
            echo "  * Already installed, found:"
            for so_file in `ls $so_files`; do
                echo "    o $so_file"
            done
        else
            download_and_install $lib
        fi
    done
}

#
# Returns Bash environmental variable configuration as a string
#
# This should be used by our Ruby env.
#
get_ruby_environment() {
    cat<<EOF

echo \$LD_LIBRARY_PATH | egrep \$env_root > /dev/null
if [ \$? -ne 0 ] ; then
    export PATH ; PATH="\$env_root/usr/bin:\$PATH"
    export LD_LIBRARY_PATH ; LD_LIBRARY_PATH="\$env_root/usr/lib:\$LD_LIBRARY_PATH"
fi

export RUBY_VERSION ; RUBY_VERSION='ruby-1.9.3-p125'
export GEM_HOME ; GEM_HOME="\$env_root/gems"
export GEM_PATH ; GEM_PATH="\$env_root/gems"
export MY_RUBY_HOME ; MY_RUBY_HOME="\$env_root/usr/lib/ruby"
export RUBYLIB ; RUBYLIB=\$MY_RUBY_HOME:\$MY_RUBY_HOME/site_ruby/1.9.1:\$MY_RUBY_HOME/1.9.1:\$MY_RUBY_HOME/1.9.1/x86_64-linux
export IRBRC ; IRBRC="\$env_root/usr/lib/ruby/.irbrc"
EOF
}

#
# Provides a wrapper for executables, it basically sets all relevant
# env variables before calling the executable in question.
#
get_wrapper_template() {
    cat<<EOF
#!/usr/bin/env bash

#
# Slight RVM rip-off
#
env_root="\$(dirname "\$(readlink -f "\${0}")")"/..
if [[ -s "\$env_root/environment" ]]; then
    source "\$env_root/environment"
    exec ruby $1 "\$@"
else
    echo "ERROR: Missing environment file: '\$env_root/environment" >&2
    exit 1
fi
EOF
}

#
# Sets the environment, updates rubygems and installs vital gems
#
prepare_ruby() {
    echo "  * Generating environment configuration ($root/environment)"

    env_root=$root
    get_ruby_environment > $root/environment
    source $root/environment

    echo "  * Updating Rubygems"
    $usr_path/bin/gem update --system &>> "$logs_path/ruby"
    handle_failure "ruby"

    echo "  * Installing Bundler"
    $usr_path/bin/gem install bundler --no-ri  --no-rdoc  &>> "$logs_path/ruby"
    handle_failure "ruby"
}

install_arachni() {
    PATH="$orig_path:$PATH"

    rm "$archives_path/arachni-pkg.tar.gz" &> /dev/null
    download $arachni_tarball_url "-O $archives_path/arachni-pkg.tar.gz"
    handle_failure "arachni"

    extract_archive "arachni"

    cd $src_path/Zapotek-arachni*

    echo "  * Preparing the bundle"
    $gem_path/bin/bundle install &>> "$logs_path/arachni"
    handle_failure "arachni"

    echo "  * Testing"
    $gem_path/bin/bundle exec $usr_path/bin/rake spec  &>> "$logs_path/arachni"
    handle_failure "arachni"

    echo "  * Installing"
    $usr_path/bin/rake install &>> "$logs_path/arachni"
    handle_failure "arachni"
}

install_bin_wrappers() {
    cd $root/gems/bin
    for bin in arachni*; do
        echo "  * $bin => $root/bin/$bin"
        get_wrapper_template "\$env_root/gems/bin/$bin" > "$root/bin/$bin"
        chmod +x "$root/bin/$bin"
    done
    cd - > /dev/null
}

echo
echo '# (1/5) Creating directories'
echo '---------------------------------'
setup_dirs

echo
echo '# (2/5) Installing dependencies'
echo '-----------------------------------'
install_libs

echo
echo '# (3/5) Preparing the Ruby environment'
echo '-------------------------------------------'
prepare_ruby

echo
echo '# (4/5) Installing Arachni'
echo '-------------------------------'
install_arachni

echo
echo '# (5/5) Installing bin wrappers'
echo '------------------------------------'
install_bin_wrappers

echo
echo '# Cleaning up'
echo '----------------'
echo "  * Removing sources"
rm -rf $src_path
echo "  * Removing downloaded archives"
rm -rf $archives_path

echo
cat<<EOF
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Installation completed succesfully!

You can add '$root/bin' to your path in order to be able to access the Arachni
executables from anywhere:

    echo 'export PATH=$root/bin:\$PATH' >> ~/.bash_profile
    source ~/.bash_profile

Useful resources:
    * Homepage     - http://arachni-scanner.com/
    * Blog         - http://arachni-scanner.com/blog
    * Wiki         - http://arachni-scanner.com/wiki
    * GitHub page  - http://github.com/zapotek/arachni
    * Google Group - http://groups.google.com/group/arachni
    * Twitter      - http://twitter.com/ArachniScanner

Have fun ;)

Cheers,
The Arachni team.

EOF
