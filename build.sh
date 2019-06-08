#!/bin/bash

build_dir=mysql-bench
pkgname=mysql-workbench
pkgver=8.0.16
pkgrel=1
_mysql_version=${pkgver}
_connector_version=${pkgver}
_gdal_version=2.4.1
_boost_version=1.69.0
_antlr_version=4.7.2

src_dir=`pwd`
build_root=${src_dir}/${build_dir}
srcdir=${build_root}
pkgdir=${src_dir}/${pkgname}_${pkgver}+dfsg-${pkgrel}

# BUILD DEPS
# unzip uuid-dev cmake swig libaio-dev libssl-dev libncurses5-dev libboost-dev antlr4 pkg-config libx11-dev libpcre3-dev libantlr4-runtime-dev
# libgtk-3-dev libgtkmm-3.0-dev libsecret-1-dev python-dev libxml2-dev libvsqlitepp-dev libssh-dev unixodbc-dev
# libzip-dev imagemagick libgdal-dev

# RUN DEPS
# libproj12
makedepends=('cmake' 'boost' 'mesa' 'swig' 'java-runtime' 'imagemagick' 'antlr4')

source_urls=("https://dev.mysql.com/get/Downloads/MySQLGUITools/mysql-workbench-community-${pkgver}-src.tar.gz"
	     "https://cdn.mysql.com/Downloads/MySQL-${_mysql_version%.*}/mysql-${_mysql_version}.tar.gz"
	     "https://cdn.mysql.com/Downloads/Connector-C++/mysql-connector-c++-${_connector_version}-src.tar.gz"
	     "http://download.osgeo.org/gdal/${_gdal_version}/gdal-${_gdal_version}.tar.xz"
	     "https://www.antlr.org/download/antlr-${_antlr_version}-complete.jar"
	     "https://downloads.sourceforge.net/project/boost/boost/${_boost_version}/boost_${_boost_version//./_}.tar.bz2"
   	     "https://git.archlinux.org/svntogit/community.git/plain/trunk/0001-mysql-workbench-no-check-for-updates.patch?h=packages/mysql-workbench"
	     "https://git.archlinux.org/svntogit/community.git/plain/trunk/0002-disable-unsupported-operating-system-warning.patch?h=packages/mysql-workbench")

get() {
	mkdir ${build_dir}
	for url in "${source_urls[@]}"; do
		echo "Getting $url";
		wget "${url}" -P ${build_root};
	done

	mv "0001-mysql-workbench-no-check-for-updates.patch?h=packages%2Fmysql-workbench" "0001-mysql-workbench-no-check-for-updates.patch"
	mv "0002-disable-unsupported-operating-system-warning.patch?h=packages%2Fmysql-workbench" "0002-disable-unsupported-operating-system-warning.patch"

}

setup(){
 cp -r bench-backup/ ${build_dir}
 cd ${build_root}
 mv "0001-mysql-workbench-no-check-for-updates.patch?h=packages%2Fmysql-workbench" "0001-mysql-workbench-no-check-for-updates.patch"
 mv "0002-disable-unsupported-operating-system-warning.patch?h=packages%2Fmysql-workbench" "0002-disable-unsupported-operating-system-warning.patch"

}

unpack(){
	cd ${build_root};
	files=${build_root}/*;
	for file in $files; do
		if [ "${file##*.}" = "gz" ] || [ "${file##*.}" = "bz2" ] || [ "${file##*.}" = "xz" ]; then
			echo "Extracting ${file}"
			tar xf $file -C ${build_root};
		fi;
	done
}

prepare(){
	cd "${build_root}/mysql-workbench-community-${pkgver}-src/"

	# Disable 'Help' -> 'Check for Updates'
	# Updates are provided via Arch Linux packages
	patch -Np1 < "${build_root}"/0001-mysql-workbench-no-check-for-updates.patch

	# disable unsupported operating system warning
	patch -Np1 < "${build_root}"/0002-disable-unsupported-operating-system-warning.patch

	# GCC 7.x introduced some new warnings, remove '-Werror' for the build to complete
	sed -i '/^set/s|-Werror -Wall|-Wall|' CMakeLists.txt

	# GCC 7.x complains about unsupported flag
	sed -i 's|-Wno-deprecated-register||' ext/scintilla/gtk/CMakeLists.txt

	# disable stringop-truncation for GCC 8.x
	sed -i '/^set/s|-Wall|-Wall -Wno-stringop-truncation|' CMakeLists.txt

	# make sure to link against bundled libraries
	sed -i "/target_link_libraries/s|\\$|-L${srcdir}/install-bundle/usr/lib/ \\$|" backend/wbpublic/CMakeLists.txt

	# change the ANTLR Version to Debian Testings current version
	sed -i 's/antlr-4.7.1-complete.jar/antlr-${_antlr_version}-complete.jar/g' CMakeLists.txt

}

build_mysql(){
	# Build mysql
	mkdir "${srcdir}/mysql-${_mysql_version}-build"
	cd "${srcdir}/mysql-${_mysql_version}-build"
	echo "Configure mysql..."
	cmake "${srcdir}/mysql-${_mysql_version}" \
		-DWITHOUT_SERVER=ON \
		-DBUILD_CONFIG=mysql_release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DSYSCONFDIR=/etc/mysql \
		-DMYSQL_DATADIR=/var/lib/mysql \
		-DWITH_BOOST="${srcdir}/boost_${_boost_version//./_}"
	echo "Build mysql..."
	make
	echo "Install mysql..."
	make DESTDIR="${srcdir}/install-bundle/" install
}

build_connector(){
	# Build mysql-connector-c++
	mkdir "${srcdir}/mysql-connector-c++-${_connector_version}-src-build"
	cd "${srcdir}/mysql-connector-c++-${_connector_version}-src-build"
	echo "Configure mysql-connector-c++..."
	cmake "${srcdir}/mysql-connector-c++-${_connector_version}-src" \
		-Wno-dev \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DINSTALL_LIB_DIR=lib \
		-DMYSQL_DIR="${srcdir}/install-bundle/" \
		-DMYSQL_CONFIG_EXECUTABLE="${srcdir}/install-bundle/usr/bin/mysql_config" \
		-DWITH_JDBC=ON
	echo "Build mysql-connector-c++..."
	make
	echo "Install mysql-connector-c++..."
	make DESTDIR="${srcdir}/install-bundle/" install
}

build_workbench(){
	# Build MySQL Workbench itself with bundled libs
	mkdir "${srcdir}/mysql-workbench-community-${pkgver}-src-build"
	cd "${srcdir}/mysql-workbench-community-${pkgver}-src-build"
	echo "Configure mysql-workbench..."
	cmake "${srcdir}/mysql-workbench-community-${pkgver}-src" \
		-Wno-dev \
		-DCMAKE_INSTALL_PREFIX:PATH=/usr \
		-DCMAKE_CXX_FLAGS="-std=c++14" \
		-DCMAKE_BUILD_TYPE=Release \
		-DMySQL_CONFIG_PATH="${srcdir}/install-bundle/usr/bin/mysql_config" \
		-DMySQLCppConn_LIBRARY="${srcdir}/install-bundle/usr/lib/libmysqlcppconn.so" \
		-DMySQLCppConn_INCLUDE_DIR="${srcdir}/install-bundle/usr/include/jdbc" \
		-DWITH_ANTLR_JAR="${srcdir}/antlr-${_antlr_version}-complete.jar" \
		-DUSE_UNIXODBC=True \
		-DUSE_BUNDLED_MYSQLDUMP=1
	echo "Build mysql-workbench..."
	make
}

build_all(){
	#build_mysql;
	#build_connector;
	build_workbench;

}

prepare_deb(){
	# Create base deb package folder structure
	echo "Create base deb package folder structure.."
	mkdir -p ${pkgdir}

	# install bundled libraries
	for LIBRARY in $(find "${srcdir}/install-bundle/usr/lib/" -type f -regex '.*/lib\(gdal\|mysql\(client\|cppconn\)\)\.so\..*'); do
		BASENAME="$(basename "${LIBRARY}")"
		SONAME="$(readelf -d "${LIBRARY}" | grep -Po '(?<=(Library soname: \[)).*(?=\])')"
		install -D -m0755 "${LIBRARY}" "${pkgdir}"/usr/lib/mysql-workbench/"${BASENAME}"
		ln -s "${BASENAME}" "${pkgdir}"/usr/lib/mysql-workbench/"${SONAME}"
	done

	# install bundled mysql and mysqldump
	install -m0755 "${srcdir}/install-bundle/usr/bin/mysql"{,dump} "${pkgdir}"/usr/lib/mysql-workbench/

	# install MySQL Workbench itself
	cd "${srcdir}/mysql-workbench-community-${pkgver}-src-build"

	make DESTDIR="${pkgdir}" install

	# icons
	for SIZE in 16 24 32 48 64 96 128; do
		# set modify/create for reproducible builds
		convert -scale ${SIZE} +set date:create +set date:modify \
			"${srcdir}/mysql-workbench-community-${pkgver}-src/images/icons/MySQLWorkbench-128.png" \
			"${srcdir}/mysql-workbench.png"
		install -D -m0644 "${srcdir}/mysql-workbench.png" "${pkgdir}/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps/mysql-workbench.png"
	done

create_deb(){

	cp -r ${src_dir}/DEBIAN ${pkgdir}
	# Setting the correct versions in debian control file
	sed -i "s/__pkg_version__+dfsg-__pkgrel__/${pkgver}+dfsg-${pkgrel}/g" ${pkgdir}/DEBIAN/control

	# changing the user to root on all files
	sudo chown -R root:root ${pkgdir}

	echo "Creating DEB file.."
	sudo dpkg -b ${pkgdir} ${src_dir}/${pkgname}_${pkgver}+dfsg-${pkgrel}_amd64.deb

	echo "All done."
}

clean(){
	cd ${src_dir}
	if [ -d ${build_dir} ]; then
		echo "Cleaning up old stuff..."
		rm -r ${build_dir};
	fi
}

clear
#clean
#setup
#get
#unpack
#prepare
#build_all
prepare_deb
create_deb
exit
