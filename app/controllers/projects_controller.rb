# frozen_string_literal: true

# A participant's projects: the list, one project, and starting a new one.
# See wiki/decisions/D-019-projects.md.
class ProjectsController < ApplicationController
  before_action :require_allowed!
  before_action :require_connected!

  def index
    @participant = current_participant
    @projects    = @participant.projects.latest.to_a
    # No project yet: the finish line is the page that says what to do.
    return redirect_to(done_path) if @projects.empty?

    @may_start_another = @participant.may_start_another_project?
  end

  def show
    @project = current_participant.projects.find(params[:id])
    @run     = @project.current_run
  end

  # Every redirect out of this action is 303. A POST answered with 302 stays
  # in browser history and Back replays it.
  def create
    participant = current_participant
    kind = params[:kind].presence_in(Project::KINDS) || "codespace"

    # The first project is always allowed. A further one only once the rule in
    # Participant#may_start_another_project? holds.
    if participant.projects.exists? && !participant.may_start_another_project?
      return redirect_to projects_path, status: :see_other,
                         alert: "Finish setting up your current project before you start another."
    end

    project = nil
    Project.transaction do
      repo_name = participant.suggested_repo_name(participant.projects.count + 1)
      project = participant.projects.create!(
        name: repo_name, kind: kind, repo_name: repo_name,
        hackatime_project_name: repo_name
      )
      run = project.provisionings.create!(participant: participant, repo_name: repo_name, status: "pending")
      ProvisionCodespaceJob.perform_later(run.id)
    end

    redirect_to project_path(project), status: :see_other
  rescue ActiveRecord::RecordNotUnique
    # Two requests raced, or a run is already in progress. Show what exists.
    redirect_to projects_path, status: :see_other
  end

  private

  # All three accounts, or back to the overview, which says which is missing.
  def require_connected!
    return if current_participant.connected?

    redirect_to start_path
  end
end
