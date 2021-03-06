class Kibana < Formula
  desc "Analytics and search dashboard for Elasticsearch"
  homepage "https://www.elastic.co/products/kibana"
  url "https://github.com/elastic/kibana.git",
      :tag      => "v6.6.0",
      :revision => "bbbacb03feb9f0de46be449c431bc03dcd15c002"
  revision 1
  head "https://github.com/elastic/kibana.git"

  bottle do
    cellar :any_skip_relocation
    sha256 "a7bea959f131f7cd05613bf661fd00f6cb5a6cfc6d7e437b99bb7546c4e7038c" => :mojave
    sha256 "96c302e6abf7f318d6d3b910cf44a40479ed894a316426b979e5fa6b55f3b4de" => :high_sierra
    sha256 "ba1fe861b4bfa541fcb59bfa01a31826682732bf328c511588ea6d23f63c7878" => :sierra
    sha256 "74680d0454747451322d944ff5878a877bc2a799ff356d9b1a4fae34c68fd285" => :x86_64_linux
  end

  resource "node" do
    url "https://nodejs.org/dist/v10.14.1/node-v10.14.1.tar.xz"
    sha256 "3def67bf1679e0606af4eb3d7ce3c0a3fe4548f2d0a87320d43a30e2207ab034"
  end

  resource "yarn" do
    url "https://yarnpkg.com/downloads/1.13.0/yarn-v1.13.0.tar.gz"
    sha256 "125d40ebf621ebb08e3f66a618bd2cc5cd77fa317a312900a1ab4360ed38bf14"
  end

  unless OS.mac?
    depends_on "python@2" => :build
    depends_on "linuxbrew/xorg/libx11"
  end

  def install
    # Reduce memory usage below 4 GB for Circle CI.
    ENV["MAKEFLAGS"] = "-j8" if ENV["CIRCLECI"]

    resource("node").stage do
      system "./configure", "--prefix=#{libexec}/node"
      system "make", "install"
    end

    # remove non open source files
    rm_rf "x-pack"
    inreplace "package.json", /"x-pack":.*/, ""

    # patch build to not try to read tsconfig.json's from the removed x-pack folder
    inreplace "src/dev/typescript/projects.ts" do |s|
      s.gsub! "new Project(resolve(REPO_ROOT, 'x-pack/tsconfig.json')),", ""
      s.gsub! "new Project(resolve(REPO_ROOT, 'x-pack/test/tsconfig.json'), 'x-pack/test'),", ""
    end

    # trick the build into thinking we've already downloaded the Node.js binary
    mkdir_p buildpath/".node_binaries/#{resource("node").version}/darwin-x64"

    # run yarn against the bundled node version and not our node formula
    (buildpath/"yarn").install resource("yarn")
    (buildpath/".brew_home/.yarnrc").write "build-from-source true\n"
    ENV.prepend_path "PATH", buildpath/"yarn/bin"
    ENV.prepend_path "PATH", prefix/"libexec/node/bin"
    system "yarn", "kbn", "bootstrap"
    system "yarn", "build", "--oss", "--release", "--skip-os-packages", "--skip-archives"

    prefix.install Dir
      .glob("build/oss/kibana-#{version}-darwin-x86_64/**")
      .reject { |f| File.fnmatch("build/oss/kibana-#{version}-darwin-x86_64/{node, data, plugins}", f) }
    mv "licenses/APACHE-LICENSE-2.0.txt", "LICENSE.txt" # install OSS license

    inreplace "#{bin}/kibana", %r{/node/bin/node}, "/libexec/node/bin/node"
    inreplace "#{bin}/kibana-plugin", %r{/node/bin/node}, "/libexec/node/bin/node"

    cd prefix do
      inreplace "config/kibana.yml", "/var/run/kibana.pid", var/"run/kibana.pid"
      (etc/"kibana").install Dir["config/*"]
      rm_rf "config"
    end
  end

  def post_install
    ln_s etc/"kibana", prefix/"config"
    (prefix/"data").mkdir
    (prefix/"plugins").mkdir
  end

  def caveats; <<~EOS
    Config: #{etc}/kibana/
    If you wish to preserve your plugins upon upgrade, make a copy of
    #{opt_prefix}/plugins before upgrading, and copy it into the
    new keg location after upgrading.
  EOS
  end

  plist_options :manual => "kibana"

  def plist; <<~EOS
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>Program</key>
        <string>#{opt_bin}/kibana</string>
        <key>RunAtLoad</key>
        <true/>
      </dict>
    </plist>
  EOS
  end

  test do
    ENV["BABEL_CACHE_PATH"] = testpath/".babelcache.json"
    assert_match /#{version}/, shell_output("#{bin}/kibana -V")
  end
end
