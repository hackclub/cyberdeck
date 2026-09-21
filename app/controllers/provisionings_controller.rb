# frozen_string_literal: true

# Starts a new run on an existing project: the retry after a failure, or the
# rebuild after the participant deleted their repository or Codespace.
class ProvisioningsController < ApplicationController
  before_action :require_allowed!

  def create
    participant = current_participant
    project     = participant.projects.find(params[:project_id])

    # A live run already holds a repository and a Codespace. A second would
    # make a second of each. Show the one that exists.
    return redirect_to(project_path(project), status: :see_other) unless project.may_retry?

    unless participant.connected?
      return redirect_to start_path, alert: "Connect your accounts first.", status: :see_other
    end

    run = project.provisionings.create!(participant: participant, repo_name: project.repo_name, status: "pending")
    ProvisionCodespaceJob.perform_later(run.id)

    redirect_to project_path(project), status: :see_other
  rescue ActiveRecord::RecordNotUnique
    # Two requests raced, or another project is mid-run. The database settled it.
    redirect_to project_path(project), status: :see_other
  end
end
