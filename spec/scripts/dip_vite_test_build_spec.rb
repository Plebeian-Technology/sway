# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "yaml"

# @lat: [[verification-gates#The frontend test bundle a spec run reads]]
RSpec.describe "the frontend test bundle a spec run reads" do
  let(:vite_build_script) { Rails.root.join("scripts", "dip", "vite-test-build.sh") }
  let(:container_entrypoint) { Rails.root.join(".dockerdev", "entrypoint.sh") }

  def hash_of(root)
    stdout, _stderr, status = Open3.capture3("bash", vite_build_script.to_s, "hash", root.to_s)
    expect(status).to be_success, "the hash subcommand failed on #{root}"
    stdout.strip
  end

  def with_frontend_tree
    Dir.mktmpdir("vite-inputs", Rails.root.join("tmp").to_s) do |dir|
      FileUtils.mkdir_p(File.join(dir, "app", "frontend", "pages"))
      File.write(File.join(dir, "app", "frontend", "pages", "Bill.tsx"), "export default 1;\n")
      File.write(File.join(dir, "package.json"), "{}\n")
      File.write(File.join(dir, "vite.config.ts"), "export default {};\n")
      yield dir
    end
  end

  it "hashes the same tree to the same value, so an unchanged frontend is not rebuilt" do
    with_frontend_tree do |dir|
      expect(hash_of(dir)).to eq(hash_of(dir))
    end
  end

  it "notices a changed frontend file, which is the whole point of the stamp" do
    with_frontend_tree do |dir|
      before = hash_of(dir)
      File.write(File.join(dir, "app", "frontend", "pages", "Bill.tsx"), "export default 2;\n")

      expect(hash_of(dir)).not_to eq(before)
    end
  end

  it "notices a new frontend file as well as an edited one" do
    with_frontend_tree do |dir|
      before = hash_of(dir)
      File.write(File.join(dir, "app", "frontend", "pages", "Legislator.tsx"), "export default 1;\n")

      expect(hash_of(dir)).not_to eq(before)
    end
  end

  it "notices a deleted frontend file, which changes the bundle as surely as an edited one" do
    with_frontend_tree do |dir|
      File.write(File.join(dir, "app", "frontend", "pages", "Legislator.tsx"), "export default 1;\n")
      before = hash_of(dir)
      File.delete(File.join(dir, "app", "frontend", "pages", "Legislator.tsx"))

      expect(hash_of(dir)).not_to eq(before)
    end
  end

  it "notices an added empty file, which contributes no bytes to hash" do
    with_frontend_tree do |dir|
      before = hash_of(dir)
      FileUtils.touch(File.join(dir, "app", "frontend", "pages", "Empty.tsx"))

      expect(hash_of(dir)).not_to eq(before),
        "the hash reads file contents alone, so a file with no contents is invisible to it — added or deleted, " \
        "the bundle is rebuilt from a different set of files and the stamp says nothing changed"
    end
  end

  it "notices a deleted empty file, the same blind spot from the other side" do
    with_frontend_tree do |dir|
      FileUtils.touch(File.join(dir, "app", "frontend", "pages", "Empty.tsx"))
      before = hash_of(dir)
      File.delete(File.join(dir, "app", "frontend", "pages", "Empty.tsx"))

      expect(hash_of(dir)).not_to eq(before)
    end
  end

  it "notices a renamed file, which moves an import without changing a byte of content" do
    with_frontend_tree do |dir|
      before = hash_of(dir)
      File.rename(
        File.join(dir, "app", "frontend", "pages", "Bill.tsx"),
        File.join(dir, "app", "frontend", "pages", "BillPage.tsx")
      )

      expect(hash_of(dir)).not_to eq(before)
    end
  end

  it "notices a changed lockfile, which changes the bundle without touching app/frontend" do
    with_frontend_tree do |dir|
      before = hash_of(dir)
      File.write(File.join(dir, "pnpm-lock.yaml"), "lockfileVersion: 9.0\n")

      expect(hash_of(dir)).not_to eq(before)
    end
  end

  it "hashes contents rather than timestamps, so a touched file rebuilds nothing" do
    with_frontend_tree do |dir|
      before = hash_of(dir)
      File.utime(1_900_000_000, 1_900_000_000, File.join(dir, "app", "frontend", "pages", "Bill.tsx"))

      expect(hash_of(dir)).to eq(before)
    end
  end

  it "refuses a subcommand it does not know rather than reporting a bundle it did not check" do
    _stdout, _stderr, status = Open3.capture3("bash", vite_build_script.to_s, "wat")

    expect(status.exitstatus).to eq(64)
  end

  it "stamps inside the build directory, so each SWAY_VITE_BUILD_DIR carries its own" do
    script = vite_build_script.read

    expect(script).to include("public/%s"),
      "the stamp is not written under the build directory, so two runs with different SWAY_VITE_BUILD_DIR " \
      "values share one stamp and each one's build satisfies the other's check"
    expect(script).to include("SWAY_VITE_BUILD_DIR")
  end

  describe "the container entrypoint" do
    let(:compose_services) do
      YAML.safe_load_file(Rails.root.join(".dockerdev", "compose.yml"), aliases: true).fetch("services")
    end

    it "is the entrypoint of both services that can be handed an rspec command" do
      %w[rails rspec].each do |name|
        expect(compose_services.fetch(name)["entrypoint"].to_s).to include("entrypoint.sh"),
          "the #{name} service has no entrypoint, so a command given on the command line replaces the compose " \
          "command and no build step runs at all"
      end
    end

    it "leaves the rspec service a command that still runs the suite" do
      expect(compose_services.fetch("rspec")["command"].to_s).to include("bundle exec rspec")
    end

    it "checks the bundle for every shape of rspec invocation" do
      script = container_entrypoint.read

      expect(script).to include("rspec"),
        "the entrypoint does not look for an rspec command, so `dip run bundle exec rspec spec/path_spec.rb` " \
        "reads whatever bundle happens to be in the shared volume"
      expect(script).to include("vite-test-build.sh ensure")
    end

    it "never builds into the directory every run's own build directory lives inside" do
      script = container_entrypoint.read

      expect(script).to match(/SWAY_VITE_BUILD_DIR="vite-test\/run-/),
        "with SWAY_VITE_BUILD_DIR unset the entrypoint builds into public/vite-test itself, the parent of every " \
        "run's own directory. Vite empties its output directory first, so that build deletes a live run's whole " \
        "bundle and every page assertion in it times out at once"
      expect(script).to include("export SWAY_VITE_BUILD_DIR"),
        "the directory the entrypoint invents is not exported, so the build writes to one directory and the Rails " \
        "process that reads the manifest looks in another"
    end

    it "hands the command through rather than wrapping it, so signals and exit codes are the command's own" do
      script = container_entrypoint.read

      expect(script).to match(/^exec "\$@"$/),
        "the entrypoint does not exec the command it was given, so a killed run leaves the entrypoint holding " \
        "the container and rspec's own exit code is not what the caller sees"
    end
  end
end
