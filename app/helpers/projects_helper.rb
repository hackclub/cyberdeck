# frozen_string_literal: true

module ProjectsHelper
  # The CSS class for one row of the step list on the project page. Rows
  # before the one the run reached are done, the row it is on is either in
  # progress or the one that broke, and rows after it are untouched.
  def step_state(run, name, steps)
    return "" if run.nil?
    return "done" if run.completed?

    index   = steps.index(name)
    current = steps.index(run.step.to_s)
    return "" if index.nil? || current.nil?

    if index < current
      "done"
    elsif index > current
      ""
    else
      run.in_progress? ? "now" : "bad"
    end
  end

  # Every state the project page can be in needs its own heading.
  def project_heading(project)
    thing = project.local? ? "repo" : "editor"
    case project.status
    when "ready" then "your #{thing} is ready"
    when "gone"  then "that setup is gone"
    when "failed" then "setup didn't finish"
    else "setting up your #{thing}"
    end
  end

  # One line under a project's name on the projects page.
  def project_status_line(project)
    case project.status
    when "ready"  then project.local? ? "Repo ready" : "Editor ready"
    when "gone"   then "Gone from GitHub"
    when "failed" then "Setup didn't finish"
    else "Setting up"
    end
  end
end
