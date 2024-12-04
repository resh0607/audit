# encoding: utf-8

module ChrnoAudit
  require "chrno_audit/version"
end

ActiveSupport.on_load( :action_controller ) do
  require "chrno_audit/action_controller_concern"
  include ChrnoAudit::ActionControllerConcern
end

ActiveSupport.on_load( :active_record ) do
  require "chrno_audit/active_record_concern"
  include ChrnoAudit::ActiveRecordConcern
end

# Если мы запускаемся в контексте рельс, то грузим Engine
if defined?( Rails ) && defined?( Rails::Engine )
  require "chrno_audit/engine"

# Иначе подключаем модели руками
else
  ActiveSupport.on_load( :active_record ) do
    Dir.glob( File.join( File.expand_path( "../../app/models", __FILE__ ), "**", "*.rb" )).each do |file|
      require file
    end
  end
end