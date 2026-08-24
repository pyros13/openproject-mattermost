# frozen_string_literal: true

# Lightweight helper so classifier specs can run without loading OpenProject.
begin
  require "rspec"
rescue LoadError
  # Installed inside the OpenProject bundle.
end
