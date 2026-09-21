# frozen_string_literal: true

require "test_helper"

# The finish line shows only until the first project exists, and a second
# project needs the first to be ready. See wiki/decisions/D-019-projects.md.
class ProjectsFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: "ident!test",
      info: { email: "ada@example.com", first_name: "Ada", last_name: "L" },
      credentials: { token: "hca" },
      extra: { raw_info: { "verification_status" => "verified", "ysws_eligible" => true } }
    )
    get "/auth/hack_club/callback"
    @participant = Participant.find_by!(hca_id: "ident!test")
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:hack_club] = nil
  end

  test "the finish line shows with all three grants and no project" do
    connect_all!
    get done_path
    assert_response :success
    assert_select "strong", text: "This is my first project"
  end

  test "creating the first project starts a run and shows the project" do
    connect_all!
    assert_enqueued_with(job: ProvisionCodespaceJob) do
      post projects_path, params: { kind: "codespace" }
    end
    project = @participant.projects.sole
    assert_redirected_to project_path(project)
    assert_equal "codespace", project.kind
    assert_equal "setting_up", project.status
    assert_equal "cyberdeck-ada", project.repo_name
    assert_equal 1, project.provisionings.count
  end

  test "the advanced card makes a local project" do
    connect_all!
    post projects_path, params: { kind: "local" }
    assert_equal "local", @participant.projects.sole.kind
    assert_equal %w[repo], @participant.projects.sole.steps
  end

  test "once a project exists the finish line and the overview lead to the projects page" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    get done_path
    assert_redirected_to projects_path
    get start_path
    assert_redirected_to done_path
  end

  test "the projects page lists the project and its state" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    get projects_path
    assert_response :success
    assert_select ".card strong", text: "cyberdeck-ada"
    assert_select ".card-status", text: "Setting up"
    assert_select "form[action=?]", projects_path, count: 0
  end

  test "a second project is refused while the first is setting up" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    post projects_path, params: { kind: "codespace" }
    assert_redirected_to projects_path
    assert_equal 1, @participant.projects.count
  end

  test "a second project is allowed once the first is ready" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    finish!(@participant.projects.sole)
    get projects_path
    assert_select "form[action=?]", projects_path
    post projects_path, params: { kind: "local" }
    assert_equal 2, @participant.projects.count
    assert_equal "cyberdeck-ada-2", @participant.projects.latest.first.repo_name
  end

  test "a run's progress is copied onto the project" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    project = @participant.projects.sole
    run = project.current_run
    run.step!("repo")
    run.update!(repo_full_name: "ada/cyberdeck-ada", repo_id: 42)
    assert_equal "ada/cyberdeck-ada", project.reload.repo_full_name
    assert_equal "https://github.com/ada/cyberdeck-ada", project.code_url
    run.update!(codespace_name: "cs", codespace_url: "https://x.github.dev")
    run.complete!
    assert project.reload.ready?
    assert_equal "https://x.github.dev", project.codespace_url
    run.mark_missing!("Your editor was deleted on GitHub.")
    assert project.reload.gone?
  end

  test "a gone project offers a new run and the project page shows why" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    project = @participant.projects.sole
    finish!(project)
    project.current_run.mark_missing!("Your editor was deleted on GitHub.")
    get project_path(project)
    assert_select "p.bad", text: "Your editor was deleted on GitHub."
    assert_select "form[action=?]", project_provisionings_path(project)
    post project_provisionings_path(project)
    assert_redirected_to project_path(project)
    assert_equal 2, project.provisionings.count
    assert project.reload.setting_up?
  end

  test "a ready project shows the editor link" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    project = @participant.projects.sole
    finish!(project)
    get project_path(project)
    assert_select "a[href=?]", "https://x.github.dev", text: "Open my editor"
    assert_select "form[action=?]", project_provisionings_path(project), count: 0
  end

  test "the live run wins over a newer dead run, as in the rows carried over" do
    connect_all!
    post projects_path, params: { kind: "codespace" }
    project = @participant.projects.sole
    finish!(project)
    live = project.current_run
    # A later run that is not live, as the 2026-09-18 migration left for Armand.
    dead = project.provisionings.create!(participant: @participant, repo_name: project.repo_name,
                                         status: "missing", created_at: 1.minute.from_now)
    assert_equal live.id, project.current_run.id
    assert project.reload.ready?, "a dead later run must not change the project"
    get project_path(project)
    assert_select "li.done", count: 3
    live.mark_missing!("Your editor was deleted on GitHub.")
    assert project.reload.gone?
    assert_equal dead.id, project.provisionings.latest.first.id
  end

  test "without every grant the projects page sends you to the overview" do
    get projects_path
    assert_redirected_to start_path
  end

  private

  def connect_all!
    @participant.update!(hackatime_api_key: "key", hackatime_user_id: "1",
                         github_token: "gho_x", github_login: "ada")
  end

  def finish!(project)
    run = project.current_run
    run.update!(repo_full_name: "ada/#{project.repo_name}", repo_id: project.id,
                codespace_name: "cs", codespace_url: "https://x.github.dev")
    run.complete!
  end
end
