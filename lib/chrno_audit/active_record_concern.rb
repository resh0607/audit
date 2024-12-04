# encoding: utf-8
module ChrnoAudit
  module ActiveRecordConcern
    extend ActiveSupport::Concern

    module ClassMethods
      def audit(*fields)
        # Existing setup code...

        # Add the relationship
        has_many :audit_records, as: :auditable, class_name: "ChrnoAudit::AuditRecord"

        # Define class attributes
        cattr_accessor :auditable_fields, :auditable_actions, :auditable_options

        # Process options...
        options = fields.extract_options!
        options.reverse_merge!(
          except: [],
          when: [:create, :update, :destroy],
          ignore_empty_diff: true
        )
        options[:except] = Array.wrap(options[:except]).map(&:to_s)
        options[:when] = Array.wrap(options[:when]).map(&:to_sym)

        if self.table_exists?
          self.auditable_fields = if fields.count == 1 && fields.first == :all
                                    column_names - %w[id created_at updated_at] - options[:except]
                                  else
                                    (fields - options[:except]).map(&:to_s)
                                  end
        end

        self.auditable_actions = options.delete(:when)
        self.auditable_options = options

        # Set up callbacks based on auditable actions
        after_create :chrno_audit_after_create if auditable_actions.include?(:create)
        after_update :chrno_audit_after_update if auditable_actions.include?(:update)
        after_destroy :chrno_audit_after_destroy if auditable_actions.include?(:destroy)

        # Include instance methods
        include InstanceMethods

      rescue ActiveRecord::NoDatabaseError
        # Handle cases where the database is not yet set up
      end
    end

    module InstanceMethods
      def chrno_audit_after_create
        create_audit_record!(:create)
      end

      def chrno_audit_after_update
        create_audit_record!(:update)
      end

      def chrno_audit_after_destroy
        create_audit_record!(:destroy)
      end

      def create_audit_record!(action, params = {}, entity: nil)
        # Return unless the action should be audited
        return unless (entity || self).class.auditable_actions.include?(action)

        # Get the changes to store and the context
        # entity will be specified, if audit call from tasks
        # for audit of instance model entity will be nil
        # When entity present and it has virtual attrs(not stored in db) they appears in entity.changes
        # not in saved_changes, so saved_changes.merge(entity.changes) needed
        has_call_from_model = entity.nil?
        entity ||= self
        all_changes = (has_call_from_model ? entity.saved_changes.merge(entity.changes) : entity.changes)
        changes_to_store = all_changes.select { |field, _| entity.class.auditable_fields.include?(field) }
        changes_to_store = real_changes(changes_to_store) if has_call_from_model

        context = get_context.with_indifferent_access

        # Return if no changes to store and not destroying
        return if entity.class.auditable_options[:ignore_empty_diff] && changes_to_store.empty? && action != :destroy

        audit_record = ChrnoAudit::AuditRecord.new do |record|
          record.action    = action.to_s
          record.auditable = entity
          record.diff      = changes_to_store
          record.initiator = context.delete(:initiator) || context.delete(:current_user)
          record.context   = context
        end

        audit_record.save! unless params[:nosave]
        audit_record
      end

      # Except fake changes for jsonb fields with serialize
      def real_changes(diff)
        keys_for_delete = diff.map { |key, change_arr| key if change_arr.first == change_arr.second }
        diff.except!(*keys_for_delete)
      end

      def get_context
        (Thread.current[:audit_context].respond_to?(:call) ? Thread.current[:audit_context].call : {}).tap do |context|
          raise "Invalid audit context: Hash expected, got: #{context.inspect}" if context && !context.is_a?(Hash)
        end
      end

      module_function :create_audit_record!, :get_context
    end
  end
end