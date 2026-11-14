# Reports sections the fork adds, appended to ReportsController's list.
module ForkReportsSections
  extend ActiveSupport::Concern

  private
    def fork_reports_sections
      projects = Current.family.projects.underway.ordered.limit(Project::SUMMARY_LIMIT).to_a
      [
        {
          key: "projects",
          title: "projects.summary.title",
          partial: "projects/summary",
          locals: { projects: projects, accounts: Current.user.accessible_accounts },
          visible: projects.any?,
          collapsible: true
        }
      ]
    end
end
