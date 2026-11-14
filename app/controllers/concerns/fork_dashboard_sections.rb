# Home widgets the fork adds. PagesController merges these into its own
# layouts and builders, so they can be reordered, resized or hidden like
# the rest.
module ForkDashboardSections
  extend ActiveSupport::Concern

  LAYOUTS = {
    "projects" => { col_span: "single", grow: false, min_height: 0, width_toggle: true }
  }.freeze

  private
    def fork_dashboard_section_builders
      {
        "projects" => -> {
          projects = dashboard_projects
          {
            key: "projects",
            title: "pages.dashboard.projects.title",
            partial: "projects/summary",
            layout: section_layout("projects"),
            locals: { projects: projects, accounts: Current.user.accessible_accounts, padded: true },
            # Shown even before the first project: on a phone this is the
            # way in, since the bottom bar has no Projects item.
            visible: true,
            collapsible: true
          }
        }
      }
    end

    def fork_hidden_dashboard_section(key)
      { key: key, title: "pages.dashboard.#{key}.title", visible: true }
    end

    def dashboard_projects
      Current.family.projects.underway.ordered.limit(Project::SUMMARY_LIMIT).to_a
    end
end
