#!/usr/bin/env ruby

require "json"
require "colored"
require "open-uri"

$DESTINATION_PATH = "/tmp/mendoza_libs"
$EXTS = ["a", "dylib"]
$ARCHS = ["x86_64", "arm64"]

def main
  system("rm -rf #{$DESTINATION_PATH}; mkdir -p #{$DESTINATION_PATH}")

  puts "Building openssl".yellow
  $ARCHS.each do |arch|
    fetch_source("https://www.openssl.org/source/openssl-3.0.8.tar.gz") # Newer versions break debug support on Apple Silicon
    openssl_path = `find #{$DESTINATION_PATH} -name 'openssl-*' -type d`.strip
    Dir.chdir(openssl_path) do
      system("./Configure darwin64-#{arch}-cc -mmacosx-version-min=12.0; make -j $(sysctl hw.ncpu | awk '{print $2}') build_libs")

      $EXTS.each do |ext|
        system("mv $(readlink -f libssl.#{ext}) ../libssl-#{arch}.#{ext}; mv $(readlink -f libcrypto.#{ext}) ../libcrypto-#{arch}.#{ext}")
      end
    end

    if arch != $ARCHS.last
      system("rm -rf #{openssl_path}")
    end
  end
  lipo(["libcrypto", "libssl"])

  openssl_path = `find #{$DESTINATION_PATH} -name 'openssl-*' -type d`.strip
  $EXTS.each do |ext|
    system("cp #{$DESTINATION_PATH}/*.#{ext} #{openssl_path}")
  end

  $ARCHS.each do |arch|
    fetch_pkg("libssh2")
    libssh2_path = `find #{$DESTINATION_PATH} -name 'libssh2-*' -type d`.strip
    Dir.chdir(libssh2_path) do
      system("export MACOSX_DEPLOYMENT_TARGET=\"10.13\"; export LDFLAGS=\"-L#{openssl_path}\"; export CFLAGS=\"-arch #{arch}\"; export CPPFLAGS=\"-arch #{arch}\"; ./configure --host=#{arch}-apple-darwin --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-examples-build --without-libz --with-crypto=openssl --with-libssl-prefix=#{openssl_path}; make -j $(sysctl hw.ncpu | awk '{print $2}')")

      $EXTS.each do |ext|
        system("mv $(readlink -f ./src/.libs/libssh2.#{ext}) ../libssh2-#{arch}.#{ext}")
      end

      if arch != $ARCHS.last
        system("rm -rf #{libssh2_path}")
      end
    end
  end
  lipo(["libssh2"])

  system("rm #{$DESTINATION_PATH}/*.dylib")

  system("sudo mkdir -p /usr/local/lib/shout; sudo mkdir -p /usr/local/include/shout")

  Dir.chdir($DESTINATION_PATH) do
    system("sudo cp *.a /usr/local/lib/shout")
    libssh2_path = `find #{$DESTINATION_PATH} -name 'libssh2-*' -type d`.strip
    system("sudo cp #{libssh2_path}/include/* /usr/local/include/shout")
  end
end

def pkg_info(name)
  unless (raw_json = `brew info #{name} --json`.strip) && (json = JSON.parse(raw_json)[0])
    puts "Run `brew install #{name}` and try again".red
    exit -1
  end

  return json
end

def source_url(json)
  unless url = json.dig("urls", "stable", "url")
    puts "Download url not found".red
    exit -1
  end

  return url
end

def fetch_pkg(name)
  puts "Fetching #{name}".yellow
  info = pkg_info(name)
  url = source_url(info)
  fetch_source(url)
end

def fetch_source(url)
  archive_path = "#{$DESTINATION_PATH}/#{File.basename(url)}"

  unless File.exist?(archive_path)
    content = URI.open(url).read
    File.write(archive_path, content)
  end

  Dir.chdir($DESTINATION_PATH) do
    system("tar zxvf #{archive_path} &>/dev/null")
  end
end

def lipo(libs)
  Dir.chdir($DESTINATION_PATH) do
    libs.each do |lib|
      $EXTS.each do |ext|
        if $ARCHS.all? { |t| `lipo -info #{lib}-x86_64.#{ext}`.include?(t) }
          system("mv #{lib}-x86_64.#{ext} #{lib}.#{ext}")
        else
          system("lipo -create #{lib}-arm64.#{ext} #{lib}-x86_64.#{ext} -output #{lib}.#{ext}")
        end

        system("rm #{lib}-arm64.#{ext}; rm #{lib}-x86_64.#{ext};")
      end
    end
  end
end

main()
