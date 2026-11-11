# frozen_string_literal: true

require "rails_helper"
require "open3"

# @lat: [[verify-sh-lane-contract-design#Why the three-state decision lives in verify-lib.sh, not in this spec]]
RSpec.describe "the cleanup in dip run verify" do
  let(:verify_script) { Rails.root.join("scripts", "dip", "verify.sh").read }

  # Comments stripped: the script's own prose about `exec` or `--name` would
  # otherwise satisfy the checks that look for them.
  let(:verify_runnable_lines) { verify_script.lines.grep_v(/\A\s*#/).join }

  # @lat: [[verify-sh-lane-contract-design#Why pinned_lane_names is a let, not a bare constant]]
  let(:pinned_lane_names) do
    %w[
      rubocop vitest tsc oxlint oxfmt
      mobile-jest mobile-tsc mobile-oxlint
      brakeman rbs-validate
      rake-gates rspec-browser rspec-nonbrowser tessdata-parity
      steep
    ]
  end

  def docker_available?
    Open3.capture3("docker", "info")[2].success?
  rescue Errno::ENOENT
    false
  end

  # @lat: [[verification-gates#What a printed rerun does and does not reproduce]]
  def expanded_lane_reruns(env = {})
    parts = [
      "RUN_ID=verifyspec",
      "SWAY_VITE_BUILD_DIR=vite-test/run-verifyspec",
      shard_counts_block,
      verify_runnable_lines[/^RAKE_GATES=\(.*?\)$/m].to_s,
      verify_runnable_lines[/^COMPOSE_RUN=.*$/].to_s,
      verify_runnable_lines[/^RSPEC_LANE_FLAGS=.*$/].to_s,
      js_worker_flag_block,
      verify_runnable_lines[/^LANE_RERUN=\(.*?\n\)$/m].to_s,
      'printf "%s\n" "${LANE_RERUN[@]}"'
    ]
    stdout, _stderr, status = Open3.capture3(env, "bash", "-c", parts.join("\n"))
    return [] unless status.success?
    stdout.lines.map(&:chomp)
  end

  # @lat: [[verification-gates#Host lanes]]
  def js_worker_flag_block
    verify_runnable_lines[/^SWAY_VERIFY_JS_WORKERS=.*?\nfi$/m].to_s
  end

  def js_worker_flag_for(value)
    env = value.nil? ? {} : {"SWAY_VERIFY_JS_WORKERS" => value}
    stdout, _stderr, status = Open3.capture3(
      env, "bash", "-c", "#{js_worker_flag_block}\nprintf '%s' \"$JS_WORKER_FLAG\""
    )
    return nil unless status.success?
    stdout
  end

  # @lat: [[verification-gates#Shard counts]]
  def shard_counts_block
    verify_runnable_lines[/^SWAY_VERIFY_BROWSER_SHARDS=.*?\nNONBROWSER_SHARDS=[^\n]*$/m].to_s
  end

  def shard_counts_for(env)
    stdout, stderr, status = Open3.capture3(
      env, "bash", "-c", "#{shard_counts_block}\nprintf '%s %s' \"$BROWSER_SHARDS\" \"$NONBROWSER_SHARDS\""
    )
    [stdout, stderr, status.exitstatus]
  end

  def shard_arguments_in(reruns)
    reruns.filter_map { |rerun| rerun[/sway:test:lane\[\w+,\d+\]/] }
  end

  def container_age_function
    verify_script[/^container_age_seconds\(\)\s*\{.*?\n\}$/m].to_s
  end

  def sweep_body
    verify_runnable_lines[/^for prefix in .*?\n(.*?)^done$/m, 1].to_s
  end

  it "exists and is not empty, so a renamed script is a red gate rather than a silent pass" do
    path = Rails.root.join("scripts", "dip", "verify.sh")
    expect(File.exist?(path)).to be(true),
      "scripts/dip/verify.sh does not exist — dip.yml's verify: interaction has nothing to run"
    expect(verify_script).not_to be_empty,
      "scripts/dip/verify.sh exists but is empty"
  end

  # @lat: [[verify-sh-lane-contract-design#Why declared_lane_names never returns nil]]
  def declared_lane_names
    match = verify_runnable_lines.match(/LANE_NAMES=\(\s*(.*?)\s*\)\n/m)
    return [] unless match
    match[1].split(/\s+/).reject(&:empty?)
  end

  # @lat: [[verify-sh-lane-contract-design#Why pinned_lane_names is a let, not a bare constant]]
  it "declares every lane in the pinned list, so a dropped lane is a red guard spec, not a quieter gate" do
    lane_names = declared_lane_names
    expect(lane_names).not_to be_empty,
      "LANE_NAMES parsed empty — either no LANE_NAMES=( ... ) array was found in scripts/dip/verify.sh, or a " \
      "change to how lanes are declared would make this example vacuously pass instead of catching a dropped lane"

    missing = pinned_lane_names - lane_names
    expect(missing).to be_empty,
      "lane(s) missing from scripts/dip/verify.sh: #{missing.inspect} — a lane silently dropped from verify " \
      "is a check that stops running while the gate keeps reporting green"
  end

  it "declares no lane beyond this spec's pinned list without updating the list here too" do
    lane_names = declared_lane_names
    extra = lane_names - pinned_lane_names
    expect(extra).to be_empty,
      "unexpected lane(s) in scripts/dip/verify.sh not in pinned_lane_names: #{extra.inspect} — update the " \
      "pinned list here deliberately if this addition is intentional"
  end

  # A duplicated lane would double-count in the summary table and could mask
  # a genuinely missing one (the pinned-list check above only sees a set
  # difference, not a count).
  it "never declares the same lane name twice" do
    lane_names = declared_lane_names
    duplicates = lane_names.tally.select { |_, count| count > 1 }.keys
    expect(duplicates).to be_empty,
      "duplicate lane name(s) in scripts/dip/verify.sh: #{duplicates.inspect} — a duplicated lane would " \
      "double-count in the summary and could mask a missing one"
  end

  # @lat: [[verify-sh-lane-contract-design#Why lane_array_entries parses arrays the way it does, and what was measured]]
  def lane_array_entries(name)
    body = verify_runnable_lines[/^#{Regexp.escape(name)}=\(\s*(.*?)\s*\)\n/m, 1]
    return [] unless body
    quoted = body.scan(/"(?:[^"\\]|\\.)*"/) #: Array[String]
    return quoted if body.include?('"')
    body.split(/\s+/).reject(&:empty?)
  end

  # @lat: [[verify-sh-lane-contract-design#Why all five index-aligned lane arrays must stay the same length]]
  it "keeps all five index-aligned lane arrays the same length" do
    names = %w[LANE_NAMES LANE_WHERE LANE_RERUN LANE_CONTAINER LANE_LOG]
    # Built by hand rather than with to_h: a two-element array literal in a
    # block reads as a plain array to the type checker, not as a pair.
    lengths = {} #: Hash[String, Integer]
    names.each { |name| lengths[name] = lane_array_entries(name).length }
    expected = lengths.fetch("LANE_NAMES")

    expect(expected).to eq(pinned_lane_names.length),
      "LANE_NAMES parsed #{expected} entries against #{pinned_lane_names.length} pinned lanes — either a lane " \
      "moved or this example's parsing no longer matches how the arrays are written"

    mismatched = lengths.reject { |_, length| length == expected }
    expect(mismatched).to be_empty,
      "lane array(s) out of step with LANE_NAMES (#{expected} entries): #{mismatched.inspect} — a short " \
      "LANE_CONTAINER is silent, and shifts every later Docker lane onto another lane's container name"
  end

  it "registers cleanup for a normal end and for an interrupt" do
    expect(verify_runnable_lines).to match(/^\s*trap\s+\w+\s+EXIT\s+INT\s+TERM\s*$/),
      "no trap on EXIT INT TERM, so an interrupted run leaves its lane containers running"
  end

  # @lat: [[verify-sh-lane-contract-design#Why cleanup kills process groups, not only containers]]
  it "kills every lane and barrier process group in cleanup, not only the containers" do
    body = verify_runnable_lines[/^cleanup\(\)\s*\{(.*?)\n\}/m, 1]
    expect(body).not_to be_nil, "no cleanup() function body found"

    expect(body).to match(/kill\s+-TERM\s+"-\$\{LANE_PID/),
      "cleanup signals no lane process group — an interrupted run leaves every host lane running, and the " \
      "rbs-validate lane goes on to rewrite the tracked rbs_collection.lock.yaml after the user has their " \
      "prompt back"
    expect(body).to match(/INSTALL_PID/),
      "cleanup signals nothing for the dependency-install barrier — an interrupt during it leaks the same way"
    expect(body).to match(/BUILD_PID/),
      "cleanup signals nothing for the frontend-build barrier — an interrupt during it leaks the same way"
  end

  # A negative pid names a process group, and a lane only HAS its own group
  # when job control is on: without `set -m` every lane shares this script's
  # group, `kill -TERM -$pid` fails outright, and the tool the lane started
  # survives.
  it "enables job control before the first background job, and starts each one with stdin closed" do
    lines = verify_runnable_lines.lines
    job_control_line = lines.find_index { |l| l.match?(/^\s*set -m\s*$/) }
    first_background_line = lines.find_index { |l| l.rstrip.match?(/(?<![&|])&\z/) }

    expect(job_control_line).not_to be_nil,
      "no set -m, so every background job shares this script's process group and kill -TERM -$pid fails — a " \
      "killed lane's own child tool keeps running"
    expect(first_background_line).not_to be_nil, "no background job found at all"
    expect(job_control_line).to be < first_background_line,
      "set -m comes after a job has already been backgrounded, so that job is not its own process group leader " \
      "and cleanup cannot signal it as one"

    # Every background start, not only the lane one: the dependency
    # install, the rbs collection install and the frontend build are each
    # backgrounded too, and each is waited on with nothing else running.
    background_starts = lines.select { |l| l.rstrip.match?(/(?<![&|])&\z/) }
    expect(background_starts.length).to be >= 4,
      "found #{background_starts.length} background start(s) — the lane start and the three barriers make " \
      "four, so this example's parsing no longer matches how they are written"
    expect(background_starts).to all(include("</dev/null")),
      "a background job is started with the terminal still on its stdin: under job control a background group " \
      "that reads the terminal is stopped by SIGTTIN, and this script would wait on it forever"
  end

  it "never hands the shell away with exec" do
    expect(verify_runnable_lines).not_to match(/^\s*exec\s/),
      "exec replaces this shell, so the trap cannot fire and no lane exit code can be read"
  end

  it "backgrounds every lane and waits on a captured pid, not only $!" do
    expect(verify_runnable_lines).to match(/&\s*$/),
      "no line ends in &, so a lane runs in the foreground and bash holds the trap until it returns"
    expect(verify_runnable_lines).to match(/wait\s+"\$\{?\w+/),
      "the script does not wait on a captured pid variable, so it can never join more than one lane"
    expect(verify_runnable_lines).not_to match(/wait\s+"\$!"/),
      "the script waits on $!, so it can only ever join one lane"
  end

  # Measured 2026-08-12: deleting `status=$?` from the cleanup handler made
  # this example fail; restoring the line passed it again.
  it "captures the exit code before cleanup and exits with it" do
    expect(verify_runnable_lines).to match(/status=\$\?/),
      "cleanup must capture $? first, or a failing lane reports as a pass"
    expect(verify_runnable_lines).to match(/exit\s+"\$status"/),
      "cleanup does not exit with the captured status, so a red lane can still exit 0"
  end

  # Measured 2026-08-12: deleting `--name "${LANE_CONTAINER[$idx]}"` from the
  # rake-gates lane made this example fail; restoring it passed again.
  it "names every container it starts, beginning with the literal sway-verify-" do
    expect(verify_runnable_lines).to match(/--name\s+"\$\{?\w+/),
      "a lane container's --name is not a variable expansion, so cleanup and the sweep cannot find it by a shared prefix"
    expect(verify_runnable_lines).to match(/=.*"sway-verify-/),
      "no container name literal begins with sway-verify- anywhere in the script, so the start-of-run sweep's name filter matches nothing"
  end

  it "sweeps stale containers before the first lane starts" do
    lines = verify_runnable_lines.lines
    sweep_line = lines.find_index { |l| l.match?(/docker (ps|rm -f)/) }
    first_lane_line = lines.find_index { |l| l.match?(/dip compose run/) }

    expect(sweep_line).not_to be_nil,
      "no docker ps / docker rm -f sweep found — a stale container from a killed run is still holding resources when the first lane starts"
    expect(first_lane_line).not_to be_nil,
      "no dip compose run lane found"
    expect(sweep_line).to be < first_lane_line,
      "the sweep runs after a lane has already started, so a stale container from a killed run is still holding CPU and memory when this lane starts"
  end

  # @lat: [[verify-sh-lane-contract-design#Why the container sweep age-gates instead of removing by container state alone]]
  it "age-gates every container it sweeps, and sweeps none in created state" do
    sweep_block = verify_runnable_lines[/^for prefix in .*?\n(.*?)^done$/m, 1].to_s
    expect(sweep_block).not_to be_empty,
      "no `for prefix in ... done` sweep block found — either the sweep is gone or this example's parsing no " \
      "longer matches how it is written, and it would pass while checking nothing"

    expect(sweep_block).not_to include("status=created"),
      "the sweep force-removes containers in created state, a state that lasts milliseconds while a concurrent " \
      "run is starting one of its own lanes — that run then reports a lane red or did-not-complete for a reason " \
      "that has nothing to do with the tree"

    removals = sweep_block.lines.grep(/docker rm -f/)
    age_gates = sweep_block.lines.grep(/-gt\s+"\$STALE_\w+_SECONDS"/)
    expect(removals.length).to be >= 2,
      "fewer than two `docker rm -f` calls in the sweep — the running and the exited branches are each meant to " \
      "have one, so this example's parsing no longer matches the sweep it is checking"
    expect(age_gates.length).to eq(removals.length),
      "#{removals.length} container removal(s) in the sweep against #{age_gates.length} age comparison(s): one " \
      "branch removes a container with no age test at all, and a concurrent run's containers are fair game to it"

    expect(verify_runnable_lines).to match(/^STALE_EXITED_CONTAINER_SECONDS=\d+$/),
      "no named threshold for an exited container's age — the number a reader reasons about and the number the " \
      "code uses can then drift apart"

    # Counting removals against age gates catches a missing gate but not a
    # wrong one: both constants match /STALE_\w+_SECONDS/, so swapping them
    # between the branches leaves the counts equal while a live run's still
    # running lane container becomes fair game after an hour.
    exited_branch, running_branch = sweep_block.split(/^\s*running=/, 2)
    expect(exited_branch.to_s).to include('-gt "$STALE_EXITED_CONTAINER_SECONDS"'),
      "the exited branch does not compare against the exited threshold — with the two thresholds swapped, a live " \
      "run's still-running lane container is force-removed after an hour"
    expect(running_branch.to_s).to include('-gt "$STALE_RUNNING_CONTAINER_SECONDS"'),
      "the running branch does not compare against the running threshold — with the two thresholds swapped, a " \
      "finished lane's container is kept for four hours and a running one is killed after one"

    # Floors, not exact values: raising either threshold is safe, lowering it
    # is what reopens the removal of a live run's containers.
    {"STALE_EXITED_CONTAINER_SECONDS" => 3600, "STALE_RUNNING_CONTAINER_SECONDS" => 14400}.each do |name, floor|
      seconds = verify_runnable_lines[/^#{name}=(\d+)$/, 1].to_i
      expect(seconds).to be >= floor,
        "#{name} is #{seconds} seconds, under the #{floor} this sweep was set to — it reaches back into a run " \
        "that is still going and removes containers that run has not read yet"
    end
  end

  # @lat: [[verification-gates#Known traps]]
  it "really removes a stale container, not only in the shape of the script that removes it" do
    skip "no docker daemon reachable from here — the sweep's own behaviour cannot be exercised" unless docker_available?

    prefix = "sway-verify-q4qat-#{Process.pid}-#{Time.now.to_i}-"
    name = "#{prefix}one"
    _, _, created = Open3.capture3("docker", "run", "--name", name, "sway-dev:1.0.0", "true")
    skip "could not start a container to sweep (#{name})" unless created.success?

    begin
      sleep 2
      script = [
        "set -u",
        "STALE_EXITED_CONTAINER_SECONDS=0",
        "STALE_RUNNING_CONTAINER_SECONDS=0",
        'SWEPT=""',
        "prefix=#{prefix.inspect}",
        container_age_function,
        sweep_body,
        'printf "SWEPT:%s\n" "$SWEPT"'
      ].join("\n")
      stdout, _stderr, status = Open3.capture3("bash", "-c", script)

      expect(status).to be_success, "the sweep block did not run to completion"
      expect(stdout).to match(/SWEPT:\s*\S/),
        "the sweep removed nothing and said so, with one stale container of its own sitting there to remove"

      surviving, _, _ = Open3.capture3("docker", "ps", "-aq", "--filter", "name=^#{prefix}")
      expect(surviving.strip).to be_empty,
        "the container is still there after the sweep ran over it, so every text assertion above describes a " \
        "sweep that does not sweep — which is why this example removes a real container instead of reading the script"
    ensure
      Open3.capture3("docker", "rm", "-f", name)
    end
  end

  # Checks nothing today, and says so in its own name: no lane is piped through
  # tee, so there is no pipeline whose exit code could be tee's instead of the
  # lane's. It arms itself the moment one is added.
  it "would put set -o pipefail before a lane, if a lane were ever piped through tee" do
    lines = verify_runnable_lines.lines
    tee_line = lines.find_index { |l| l.match?(/\|\s*tee\b/) }

    if tee_line
      pipefail_line = lines.find_index { |l| l.match?(/^\s*set -o pipefail\s*$/) }
      expect(pipefail_line).not_to be_nil,
        "a lane pipes through tee but no set -o pipefail appears anywhere, so that lane's exit code is tee's, not its own"
      expect(pipefail_line).to be < tee_line,
        "set -o pipefail appears after the tee pipeline it must guard, so that lane's exit code is tee's, not its own"
    end
  end

  it "refuses arguments, matching rspec.sh's refusal and its exit code 64" do
    expect(verify_runnable_lines).to match(/\$#.*-gt\s+0/),
      "the script does not check for arguments, so dip run verify --anything silently attempts to run"
    expect(verify_runnable_lines).to match(/exit\s+64/),
      "the argument refusal does not exit 64, matching rspec.sh's contract"
  end

  it "writes a summary.json under tmp/verify" do
    expect(verify_runnable_lines).to match(%r{tmp/verify.*summary\.json}),
      "no summary.json is written under tmp/verify — a subagent has nothing machine-readable to read back"
  end

  # Measured 2026-08-13: deleting the `SWAY_VITE_BUILD_DIR="vite-test/run-$RUN_ID"`
  # assignment made this example fail (no such line found); restoring it passed
  # again.
  it "sets SWAY_VITE_BUILD_DIR before the first lane's compose run" do
    lines = verify_runnable_lines.lines
    build_dir_line = lines.find_index { |l| l.match?(/^\s*SWAY_VITE_BUILD_DIR=/) }
    first_lane_compose_run_line = lines.find_index { |l| l.match?(/compose.*run.*LANE_CONTAINER/) }

    expect(build_dir_line).not_to be_nil,
      "no SWAY_VITE_BUILD_DIR=... assignment found — the barrier never sets this run's own build directory"
    expect(first_lane_compose_run_line).not_to be_nil,
      "no lane's compose run found inside run_lane()"
    expect(build_dir_line).to be < first_lane_compose_run_line,
      "SWAY_VITE_BUILD_DIR is set after a lane's own compose run, so that lane's container would not receive " \
      "this run's build directory through its -e flag"
  end

  # Measured 2026-08-13: deleting the `if [ "$BUILD_EXIT" != "0" ]; then ... exit 1; fi`
  # branch made this example fail (no build-failure branch found); restoring
  # it passed again.
  it "aborts before any lane starts when the frontend build fails" do
    lines = verify_runnable_lines.lines
    build_failure_line = lines.find_index { |l| l.match?(/frontend build failed/) }
    first_lane_start_line = lines.find_index { |l| l.match?(/LANE_PID\[\$idx\]=\$!/) }

    expect(build_failure_line).not_to be_nil,
      "no build-failure branch found — a failed frontend build would not be reported or would not stop the run"
    expect(first_lane_start_line).not_to be_nil,
      "no lane-start loop found (LANE_PID[$idx]=$!)"
    expect(build_failure_line).to be < first_lane_start_line,
      "the build-failure branch runs after a lane has already started, so a failed build no longer stops the " \
      "run before lanes begin — nothing downstream would be valid, but lanes would run anyway"
  end

  # Anchored to start-of-line so this only matches the case label inside
  # run_lane() -- without ^, "rspec-nonbrowser)" also matches mid-line inside
  # the LANE_NAMES=(... rspec-nonbrowser) array literal, which has no ;; of
  # its own and would swallow everything up to some unrelated later one.
  def run_lane_case_block(lane_name)
    verify_runnable_lines[/^\s*#{Regexp.escape(lane_name)}\)(.*?);;/m, 1]
  end

  # Scoped to run_lane()'s own body so an example asking "does only the browser
  # lane carry this flag" is answered by the invocations themselves, not by
  # LANE_RERUN or by the script's prose about either.
  def run_lane_body
    verify_runnable_lines[/run_lane\(\)\s*\{(.*?)\n\}/m, 1]
  end

  # Every `name)` label inside run_lane(), in declaration order. Never nil, for
  # the same reason declared_lane_names is not: an empty array is the "nothing
  # parsed" signal, so callers make one check rather than two. The `*)`
  # catch-all is deliberately not one of these -- it is not a lane.
  def run_lane_case_labels
    body = run_lane_body
    return [] unless body
    body.scan(/^\s*([A-Za-z0-9_-]+)\)$/).flatten
  end

  # @lat: [[verify-sh-lane-contract-design#Why bash's case fallthrough makes an explicit catch-all mandatory]]
  it "gives every declared lane its own branch in run_lane, so no lane can report green having run nothing" do
    labels = run_lane_case_labels
    expect(labels).not_to be_empty,
      "no case labels parsed out of run_lane() — this example would otherwise pass while checking nothing"

    missing = declared_lane_names - labels
    expect(missing).to be_empty,
      "lane(s) declared in LANE_NAMES with no run_lane() branch: #{missing.inspect} — a lane with no branch " \
      "runs nothing, exits 0 and is classified green"

    extra = labels - declared_lane_names
    expect(extra).to be_empty,
      "run_lane() branch(es) for lane(s) not in LANE_NAMES: #{extra.inspect} — that branch never runs, so the " \
      "check it holds is not part of the gate"
  end

  it "refuses an unknown lane name in run_lane rather than falling through the case and returning 0" do
    body = run_lane_body
    expect(body).not_to be_nil, "no run_lane() function body found"
    expect(body).to match(/^\s*\*\)/),
      "run_lane() has no *) catch-all, so a lane name with a typo'd or renamed branch matches nothing, returns " \
      "0, and is classified green having run nothing"
    catch_all = body.to_s[/^\s*\*\)(.*?);;/m, 1]
    expect(catch_all).not_to be_nil, "the *) catch-all has no body"
    expect(catch_all).to match(/return\s+[2-9]/),
      "the *) catch-all does not return an exit code outside {0,1}, so the lane would be classified green or " \
      "red rather than did-not-complete — the honest state for a lane that never ran"
  end

  # @lat: [[verify-sh-lane-contract-design#Why the browser lane alone carries SWAY_REQUIRE_BROWSER=1]]
  it "carries SWAY_REQUIRE_BROWSER=1 on the browser lane and no other lane" do
    body = run_lane_body
    expect(body).not_to be_nil, "no run_lane() function body found"

    browser_block = run_lane_case_block("rspec-browser")
    expect(browser_block).not_to be_nil, "no rspec-browser) case branch found in run_lane()"
    expect(browser_block).to include("SWAY_REQUIRE_BROWSER=1"),
      "the browser lane does not carry SWAY_REQUIRE_BROWSER=1 — a shard that loses its browser would drop its " \
      "examples and the run would still report green"

    other_lanes_body = body.to_s.sub(browser_block.to_s, "")
    expect(other_lanes_body).not_to include("SWAY_REQUIRE_BROWSER"),
      "a lane other than rspec-browser carries SWAY_REQUIRE_BROWSER — only the browser lane may refuse to skip " \
      "a missing browser"
  end

  # @lat: [[verify-sh-lane-contract-design#Why both rspec lanes need their own SWAY_TEST_DATABASE_DIR]]
  it "gives both rspec lanes their own SWAY_TEST_DATABASE_DIR" do
    %w[rspec-browser rspec-nonbrowser].each do |lane|
      block = run_lane_case_block(lane)
      expect(block).not_to be_nil, "no #{lane}) case branch found in run_lane()"
      expect(block).to include("SWAY_TEST_DATABASE_DIR=/testdb"),
        "the #{lane} lane does not set SWAY_TEST_DATABASE_DIR — its workers would fall back to the shared " \
        "storage/test.sqlite3 and collide with every other run on this machine"
    end
  end

  # @lat: [[verify-sh-lane-contract-design#Why the two rspec lanes each name themselves in SWAY_TEST_LANE]]
  it "names its own lane on each rspec lane, so the two lanes' coverage slices cannot collide" do
    {"rspec-browser" => "browser", "rspec-nonbrowser" => "nonbrowser"}.each do |lane, value|
      block = run_lane_case_block(lane)
      expect(block).not_to be_nil, "no #{lane}) case branch found in run_lane()"
      expect(block).to include("SWAY_TEST_LANE=#{value}"),
        "the #{lane} lane does not name itself, so its workers share SimpleCov command names with the other " \
        "rspec lane and one lane's coverage slice overwrites the other's"
    end

    rails_helper = Rails.root.join("spec", "rails_helper.rb").read
    expect(rails_helper).to match(/SimpleCov\.command_name.*SWAY_TEST_LANE/),
      "spec/rails_helper.rb does not put the lane in SimpleCov's command name, so passing SWAY_TEST_LANE from " \
      "verify.sh changes nothing — these two files have to agree"
  end

  it "gives both rspec lanes this run's own SWAY_VITE_BUILD_DIR" do
    %w[rspec-browser rspec-nonbrowser].each do |lane|
      block = run_lane_case_block(lane)
      expect(block).not_to be_nil, "no #{lane}) case branch found in run_lane()"
      expect(block).to match(/SWAY_VITE_BUILD_DIR="\$SWAY_VITE_BUILD_DIR"/),
        "the #{lane} lane does not pass this run's own SWAY_VITE_BUILD_DIR — it would build or read the wrong " \
        "frontend manifest"
    end
  end

  # @lat: [[verify-sh-lane-contract-design#Why no lane container carries --rm, separately from the sweep]]
  it "leaves each named lane container in place for classify_lane to read, and removes it in cleanup" do
    declared_lane_names.each do |lane|
      block = run_lane_case_block(lane).to_s
      next unless block.include?("--name")

      expect(block).not_to include("--rm"),
        "the #{lane} lane removes its own container as part of the run, so its exit code and OOM flag are gone " \
        "before classify_lane can read them"
    end

    cleanup_body = verify_runnable_lines[/^cleanup\(\)\s*\{(.*?)\n\}/m, 1]
    expect(cleanup_body).to match(/docker rm -f "\$\{LANE_CONTAINER/),
      "cleanup does not remove the lane containers, and no lane removes its own — every run would leave its " \
      "containers behind"
  end

  # @lat: [[verify-sh-lane-contract-design#Why brakeman's exit codes are read specially in classify_lane]]
  it "counts brakeman's own exit codes as a result rather than a crash" do
    body = verify_runnable_lines[/classify_lane\(\)\s*\{(.*?)\n\}/m, 1]
    expect(body).not_to be_nil, "no classify_lane() function body found"

    arm = body.to_s[/^\s*brakeman\)(.*)$/, 1]
    expect(arm).not_to be_nil,
      "classify_lane has no brakeman arm, so the security lane is judged by the shared 0-or-1 rule and a real " \
      "finding (exit 3) is reported did-not-complete instead of red"
    expect(arm).to match(/(\A|\D)3(\D|\z)/),
      "the brakeman arm does not accept exit 3 (warnings found), so a genuine security finding is reported as " \
      "a crash and re-running produces the same crash every time"
    expect(arm).to match(/(\A|\D)7(\D|\z)/),
      "the brakeman arm does not accept exit 7 (errors raised inside brakeman), the other code its own " \
      "commandline raises under the flags this lane uses"
  end

  # @lat: [[verify-sh-lane-contract-design#Why the rbs collection install barrier must run before any lane starts]]
  it "installs the rbs collection before any lane starts, not inside a lane, and reports a failed install" do
    lines = verify_runnable_lines.lines
    # Anchored to the start of a line: LANE_RERUN's entry for this lane holds
    # the same words inside a quoted string, so a search over the whole file
    # matches it and stays green with the barrier itself deleted.
    barrier_line = lines.find_index { |l| l.match?(/^\s*bundle exec rbs collection install\b/) }
    first_lane_start_line = lines.find_index { |l| l.match?(/LANE_PID\[\$idx\]=\$!/) }

    expect(barrier_line).not_to be_nil,
      "nothing runs `rbs collection install` outside LANE_RERUN's copy-pasteable rerun string, so the " \
      "rbs-validate lane has no gem signatures to check"
    expect(first_lane_start_line).not_to be_nil,
      "no lane-start loop found (LANE_PID[$idx]=$!)"
    expect(barrier_line).to be < first_lane_start_line,
      "the rbs collection install runs after the lanes have started, so it rewrites rbs_collection.lock.yaml " \
      "while the oxfmt lane may be reading it — that race makes the gate go red at random on a clean tree"

    expect(run_lane_body.to_s).not_to include("rbs collection install"),
      "a lane rewrites rbs_collection.lock.yaml while the oxfmt lane may be reading it — same race, from inside " \
      "a lane rather than after the lane-start loop"

    expect(run_lane_case_block("rbs-validate").to_s).to include("RBS_INSTALL_EXIT"),
      "the rbs-validate lane does not read the barrier's recorded exit code, so a failed install is a silent " \
      "skip rather than one red lane"
  end

  it "never wraps a lane command in bash -c" do
    expect(verify_runnable_lines).not_to match(/bash -c/),
      "a bash -c wrapper can swallow a lane's real output and exit 0 having printed only shell chatter"
  end

  # @lat: [[verify-sh-lane-contract-design#Why verify.sh takes no lock around any lane]]
  it "runs no lock around any lane -- two full runs are meant to overlap" do
    expect(verify_runnable_lines).not_to match(/\bflock\b/),
      "a flock call would serialize two verify runs against each other, contradicting the no-lock decision"
    expect(verify_runnable_lines).not_to match(/LOCK_(EX|SH)/),
      "an explicit lock-mode constant suggests a run lock crept back in, contradicting the no-lock decision"
  end

  # @lat: [[verify-sh-lane-contract-design#Why the three-state decision lives in verify-lib.sh, not in this spec]]

  # A red lane needs a way back in, not just somewhere to look. The
  # command reaches summary.json either way; a person reading a red table does
  # not open summary.json.
  it "prints each red lane's rerun command beside its log path" do
    expect(verify_runnable_lines).to match(/see \$\{LANE_LOG\[\$idx\]\}"\n\s*echo "\s*rerun: \$\{LANE_RERUN\[\$idx\]\}"/),
      "the red/did-not-complete report names a log file without the command that reproduces the lane, so the " \
      "rerun stays in summary.json where nobody reading the table will find it"
  end

  # @lat: [[verification-gates#What a printed rerun does and does not reproduce]]
  describe "the rerun printed beside a red lane" do
    let(:reruns) { expanded_lane_reruns }

    it "expands to one command per lane" do
      expect(reruns.length).to eq(declared_lane_names.length),
        "the LANE_RERUN array did not expand to one command per lane, so every example below would compare " \
        "a lane against another lane's command"
    end

    it "passes every variable its own lane passes" do
      names = declared_lane_names

      names.each_with_index do |name, index|
        block = run_lane_case_block(name).to_s
        passed = block.scan(/-e\s+([A-Z_]+)=/).flatten.uniq
        next if passed.empty?

        rerun = reruns[index].to_s
        missing = passed.reject { |variable| rerun.include?(variable) }

        expect(missing).to be_empty,
          "the #{name} rerun drops #{missing.join(", ")}, so pasting it runs a different configuration from the " \
          "lane it names — a shared test database, a stale frontend build, or a coverage slice that overwrites " \
          "the other lane's"
      end
    end

    it "names this run's own frontend build directory wherever the lane read one" do
      names = declared_lane_names

      names.each_with_index do |name, index|
        next unless run_lane_case_block(name).to_s.include?("SWAY_VITE_BUILD_DIR")

        expect(reruns[index].to_s).to include("vite-test/run-verifyspec"),
          "the #{name} rerun names no build directory, so it reads the shared public/vite-test, which may hold a " \
          "stale build or another run's"
      end
    end

    it "carries no -e flag through dip compose run, which re-splits the line it is given" do
      offenders = reruns.select { |rerun| rerun.include?("-e ") && rerun.include?("dip compose run") }

      expect(offenders).to be_empty,
        "these reruns pass -e flags through `dip compose run`, whose second shell re-splits an already-glued " \
        "argument line, so the flags never reach the container and the command only looks right:\n" +
          offenders.join("\n")
    end

    it "says what a rerun cannot supply, so a skip is not read as a pass" do
      expect(verify_runnable_lines).to match(/RUSTRAK_DSN[^\n]*unset|no error collector is started/),
        "the red report does not say that a rerun starts no error collector, so an example that skips for want " \
        "of it reads as a pass to whoever is deciding whether the red is real — measured 2026-08-17 on " \
        "spec/system/browser_error_reporting_spec.rb, which skips in a rerun because --no-deps starts no collector"
    end
  end

  it "gives the browser lane a rerun that still refuses a missing browser" do
    entries = verify_runnable_lines[/LANE_RERUN=\((.*?)\n\)/m, 1]
    expect(entries).not_to be_nil, "no LANE_RERUN array found"

    browser_rerun = entries.to_s.lines.find { |line| line.include?("sway:test:lane[browser") }
    expect(browser_rerun).not_to be_nil, "no browser entry in LANE_RERUN"

    expect(browser_rerun).to include("SWAY_REQUIRE_BROWSER=1"),
      "the browser lane's rerun drops SWAY_REQUIRE_BROWSER, so the command handed to whoever is investigating a " \
      "browser red skips every browser example on a machine with no Chrome and answers green -- the outcome SWAY_REQUIRE_BROWSER " \
      "exists to prevent, reintroduced at the moment someone is trying to reproduce a failure"
    expect(browser_rerun).not_to match(/\bdip compose run\b/),
      "the browser lane's rerun goes through `dip compose run`, whose second shell re-splits an already-glued " \
      "argument line -- its SWAY_REQUIRE_BROWSER would never reach the container, so the command would only look right"
  end

  # @lat: [[verification-gates#Docker lanes]]
  it "puts the lint lane's own gate counts in summary.json, not only in its log" do
    body = verify_runnable_lines[/classify_lane\(\)\s*\{(.*?)\n\}/m, 1].to_s
    expect(body).to include("rake_gates_totals"),
      "classify_lane never reads the rake-gates lane's own summary line, so summary.json cannot tell one failed " \
      "gate from five that never ran — with six gates behind one lane exit code, the log is the only place " \
      "that answer lives"

    facts = verify_runnable_lines[/printf '(?:%s\\t)+%s\\n'.*?>>"\$FACTS_FILE"/m].to_s
    expect(facts).to include("LANE_CHECKS_RAN"),
      "the gate counts are read and then dropped before the facts file, so they never reach summary.json"
    expect(facts).to include("LANE_CHECKS_FAILED")

    columns = facts[/printf '((?:%s\\t)+%s)\\n'/, 1].to_s.split('\t').length
    expect(columns).to eq(11),
      "the facts row writes #{columns} columns; verify-summary.mjs destructures eleven, so a lane's counts land " \
      "in the wrong field or nowhere"

    expect(body).to match(/lane_state \\\n\s*"\$docker_exit".*\n\s*"\$counted" "\$counted_failed"/),
      "lane_state is judged on the rspec counts alone, so a rake-gates lane that ran no gate at all still " \
      "reports green"
  end

  # @lat: [[verification-gates#Known traps]]
  describe "a summary that cannot be written" do
    let(:final_guard) do
      verify_script[/^if ! write_summary "\$FACTS_FILE" "\$EXIT_CODE"; then\n.*?^fi$/m]
    end

    it "guards every write_summary call, so a summary failure cannot abort the run under set -e" do
      bare = verify_runnable_lines.lines.select do |line|
        line.match?(/(\A|[^!\s])\s*write_summary\s+"/) && !line.match?(/^\s*if ! write_summary/)
      end

      expect(bare).to be_empty,
        "an unguarded write_summary aborts the whole script the moment its node step or its copy fails, taking " \
        "the lane table, the rerun hints and the computed exit code with it:\n" + bare.join
    end

    it "keeps the run going and says so when the summary write fails" do
      expect(final_guard).not_to be_nil,
        "no guarded write_summary call found at the end of the run, so a summary failure still ends the run there"

      script = <<~BASH
        set -eu
        EXIT_CODE=2
        FACTS_FILE=/dev/null
        write_summary() { return 1; }
        #{final_guard}
        echo REACHED
      BASH
      stdout, stderr, status = Open3.capture3("bash", "-c", script)

      expect(status).to be_success
      expect(stdout).to include("REACHED"),
        "a failing write_summary stops the script before the lane table, so a run that computed 2 exits 1"
      expect(stderr).to match(/summary could not be written/),
        "the summary write failed silently, so nobody reading the table knows tmp/verify/summary.json is stale"
    end

    it "guards the failing-example list too, which reads the summary the step above may not have written" do
      expect(verify_runnable_lines).to match(/if ! SUMMARY_PATH=[^\n]*verify-failing-examples\.mjs; then/),
        "the failing-example list reads $RUN_DIR/summary.json unguarded, so a missing summary aborts the run " \
        "after the table has printed and the computed exit code is replaced by node's"
    end
  end

  # @lat: [[verification-gates#Host lanes]]
  describe "the JS worker cap" do
    it "declares the switch and computes a flag from it" do
      expect(js_worker_flag_block).not_to be_empty,
        "no SWAY_VERIFY_JS_WORKERS block found in scripts/dip/verify.sh, so every example below would pass " \
        "against an empty string rather than against the cap the gate applies"
    end

    it "caps both JS pools when the switch is unset, so the default gate does not oversubscribe the machine" do
      expect(js_worker_flag_for(nil)).to eq("--maxWorkers=2"),
        "the gate's default is uncapped again: vitest and mobile jest each take roughly cores-1 workers on top " \
        "of thirteen other lanes, and capping them measured 15% faster over six alternating runs on 2026-09-05"
    end

    it "honours a value other than the default" do
      expect(js_worker_flag_for("4")).to eq("--maxWorkers=4")
    end

    it "passes no flag at all when the switch disables the cap" do
      expect(js_worker_flag_for("0")).to eq(""),
        "SWAY_VERIFY_JS_WORKERS=0 still passes --maxWorkers, so the uncapped arm of a measurement measures the " \
        "capped one"
      expect(js_worker_flag_for("uncapped")).to eq("")
    end

    it "hands the flag to the vitest and mobile-jest lanes and to no other lane" do
      carrying = declared_lane_names.select do |name|
        run_lane_case_block(name).to_s.include?("$JS_WORKER_FLAG")
      end

      expect(carrying).to match_array(%w[vitest mobile-jest]),
        "the lanes reading the cap are #{carrying.inspect}; only the two lanes that start worker pools of their " \
        "own may read it, and both of them must"
    end

    it "prints the cap in each JS lane's rerun, so a pasted rerun runs the pool the lane ran" do
      names = declared_lane_names
      reruns = expanded_lane_reruns

      names.each_with_index do |name, index|
        next unless %w[vitest mobile-jest].include?(name)

        rerun = reruns[index].to_s
        expect(rerun).to include("--maxWorkers="),
          "the #{name} rerun drops the worker cap, so pasting it runs a pool the size of the machine while the " \
          "lane it names ran a capped one"
      end
    end
  end

  # @lat: [[verification-gates#Shard counts]]
  describe "the rspec shard counts" do
    let(:overrides) { {"SWAY_VERIFY_BROWSER_SHARDS" => "3", "SWAY_VERIFY_NONBROWSER_SHARDS" => "5"} }

    it "declares both switches and derives each lane's count from its own" do
      expect(shard_counts_block).not_to be_empty,
        "no SWAY_VERIFY_BROWSER_SHARDS ... NONBROWSER_SHARDS block found in scripts/dip/verify.sh, so every " \
        "example below would run against an empty string rather than against the counts the gate applies"
    end

    it "runs 2 browser and 4 non-browser shards when the switches are unset, the CPU-budget setting" do
      stdout, _stderr, exit_code = shard_counts_for({})
      expect(exit_code).to eq(0)
      expect(stdout).to eq("2 4"),
        "the default shard counts moved from 2 and 4: at 4 and 6 the two rspec lanes drew about eleven average " \
        "cores on the ten-core VM while eleven host lanes ran beside them"
    end

    it "honours a value other than the default on each switch" do
      stdout, _stderr, exit_code = shard_counts_for(overrides)
      expect(exit_code).to eq(0)
      expect(stdout).to eq("3 5")
    end

    it "refuses anything but a positive integer with exit code 64, the code an argument earns" do
      %w[0 00 -1 1.5 four].each do |value|
        %w[SWAY_VERIFY_BROWSER_SHARDS SWAY_VERIFY_NONBROWSER_SHARDS].each do |switch|
          _stdout, stderr, exit_code = shard_counts_for(switch => value)
          expect(exit_code).to eq(64),
            "#{switch}=#{value.inspect} was accepted (exit #{exit_code}), so the lane would hand that value to " \
            "sway:test:lane and start a shard arrangement nobody measured"
          expect(stderr).to include(switch),
            "the refusal of #{switch}=#{value.inspect} does not name the switch, so the operator has to guess " \
            "which of the two to fix"
        end
      end
    end

    it "prints the resolved counts in each rspec lane's rerun, so a pasted rerun runs the shards the lane ran" do
      expect(shard_arguments_in(expanded_lane_reruns))
        .to eq(["sway:test:lane[browser,2]", "sway:test:lane[nonbrowser,4]"]),
          "the default reruns do not carry the default counts, so pasting one runs a different shard " \
          "arrangement from the lane it names"
      expect(shard_arguments_in(expanded_lane_reruns(overrides)))
        .to eq(["sway:test:lane[browser,3]", "sway:test:lane[nonbrowser,5]"]),
          "an overridden count did not reach both reruns, so the rerun printed beside a red lane names a shard " \
          "arrangement the lane did not run"
    end
  end

  # @lat: [[verify-sh-lane-contract-design#Why verify.sh prints progress lines during the barriers and each lane]]
  describe "progress reporting" do
    it "announces each of the three barriers that run before any lane starts" do
      %w[1 2 3].each do |n|
        expect(verify_runnable_lines).to match(/progress "barrier #{n} of 3/),
          "barrier #{n} of 3 starts without saying so, so the longest silence in the run -- the barriers, before " \
          "any lane exists to report on -- stays unexplained"
      end
    end

    it "hands every lane the terminal as fd 3, so its completion line is not swallowed by its own log" do
      starts = verify_runnable_lines.lines.select { |l| l.include?("run_lane_wrapped") && l.rstrip.end_with?("&") }
      expect(starts).not_to be_empty, "no backgrounded run_lane_wrapped call found"

      expect(starts).to all(match(/3>&2\s+>"\$\{LANE_LOG/)),
        "a lane is started without 3>&2 ahead of its log redirect, so fd 3 is either closed or points at the log " \
        "itself -- that lane finishes in silence, and under set -e a closed fd 3 aborts the wrapper before it can " \
        "stamp .lane-end, which also breaks the duration this lane reports"
    end

    it "writes the lane completion line to fd 3 rather than to the lane's own stdout or stderr" do
      body = verify_runnable_lines[/^run_lane_wrapped\(\)\s*\{(.*?)\n\}/m, 1]
      expect(body).not_to be_nil, "no run_lane_wrapped() function body found"

      expect(body).to match(/printf[^\n]*>&3\s*$/),
        "the wrapper's completion line does not go to fd 3, so it lands in the lane's log file with the lane's own " \
        "output and never reaches the screen -- the gate is silent again while looking correct in the logs"
    end

    it "reports a finished lane's exit code without calling it red, which only classify_lane can decide" do
      body = verify_runnable_lines[/^run_lane_wrapped\(\)\s*\{(.*?)\n\}/m, 1]

      expect(body).not_to match(/printf[^\n]*(red|green|did-not-complete)/),
        "the wrapper prints a verdict, but it cannot read the container: a lane killed for memory exits non-zero " \
        "and is did-not-complete, not red, so a verdict here would contradict the summary table below it"
    end
  end
end
