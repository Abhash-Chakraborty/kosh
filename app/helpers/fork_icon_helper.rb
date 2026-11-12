# Icons this fork swaps wherever upstream uses them. Prepended to
# ApplicationHelper (config/initializers/fork_icons.rb) so every caller of
# `icon`, including design system components, gets the swap without a change
# to an upstream view.
module ForkIconHelper
  # Sparkle glyphs mark AI features upstream; here those features are named
  # in words and carry a plain icon.
  REPLACEMENTS = {
    "sparkles" => "zap",
    "sparkle" => "zap",
    "wand-sparkles" => "zap"
  }.freeze

  def icon(key, **options)
    super(REPLACEMENTS.fetch(key.to_s.strip.downcase, key), **options)
  end
end
