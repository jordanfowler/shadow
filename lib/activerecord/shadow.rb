# Copyright (c) 2008 Jordan Fowler
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module ActiveRecord
  class ShadowAttachmentError < ActiveRecordError
    def initialize(owner_class_name, attachment)
      super("Expected attached #{attachment} on #{owner_class_name}.")
    end
  end

  module Acts
    module Shadow
      def self.included(base)
        base.extend BaseClassMethods
      end

      module BaseClassMethods
        def shadow(options = {})
          return if self.included_modules.include?(ActiveRecord::Acts::Shadow::BaseClassMethods::ShadowInstanceMethods)
          self.send :cattr_accessor, *[
            :skip_attributes, :shadowed_attributes, :skip_associations, :shadowed_associations, :shadowed_attachments
          ]

          self.send :include, ShadowInstanceMethods
          self.send :extend,  ShadowClassMethods

          self.skip_attributes = [
            [options[:skip_attributes]].flatten.compact.collect(&:to_s), ['created_at', 'updated_at', 'id', 'version']
          ].flatten.compact

          self.skip_associations = [
            [options[:skip_associations], :versions].flatten.compact.collect(&:to_sym)
          ].flatten.compact

          self.shadowed_attributes = case options[:attributes]
          when :none then []
          when Array then options[:attributes].flatten.collect(&:to_s) - self.skip_attributes
          else self.columns.collect(&:name) - self.skip_attributes
          end

          self.shadowed_associations = case options[:associations]
          when :none then []
          when Array then options[:associations].flatten.collect(&:to_sym) - self.skip_associations
          else self.reflect_on_all_associations.collect(&:name) - self.skip_associations
          end

          self.shadowed_attachments = case options[:attach]
          when Symbol, Array then [options[:attach]].flatten.compact.collect(&:to_sym)
          else []
          end

          class_eval do
            attr_accessor :updated_attributes
            attr_accessor :updated_associations

            build_instance_attachments
            build_association_attachments
            build_association_callbacks

            has_many(:attribute_updates, {
              :class_name => "#{self.to_s}::AttributeShadow",
              :foreign_key => self.to_s.foreign_key
            })
            has_many(:association_updates, {
              :class_name => "#{self.to_s}::AssociationShadow",
              :foreign_key => self.to_s.foreign_key
            })

            before_save :determine_updated_attributes
            after_save  :store_updated_attributes

            const_set('AttributeShadow', Class.new(ActiveRecord::Base)).class_eval do
              serialize :updated_attributes, Array

              before_save do |shadow|
                shadow.updated_attributes ||= []
              end
            end

            self::AttributeShadow.class_eval <<-END
              def #{self.to_s.underscore}
                @#{self.to_s.underscore} ||= if self.version.blank?
                  ::#{self.to_s}.find(self.#{self.to_s.foreign_key})
                else
                  ::#{self.to_s}.find(self.#{self.to_s.foreign_key}).versions.find_by_version(self.version)
                end
              end
            END

            const_set('AssociationShadow', Class.new(ActiveRecord::Base)).class_eval do
              before_save do |shadow|
                shadow.association = shadow.association.to_s
                shadow.action = shadow.action.to_s
              end

              def record
                @record ||= if self.record_version.blank?
                  self.association.to_s.classify.constantize.find(self.record_id)
                else
                  self.association.to_s.classify.constantize.find(self.record_id).versions.find_by_version(self.record_version)
                end
              end
            end
          end

          self::AssociationShadow.class_eval <<-END
            belongs_to :#{self.to_s.underscore}, :class_name => "::#{self.to_s}"
          END

          self.shadowed_attachments.each do |attachment|
            [self::AttributeShadow, self::AssociationShadow].each do |klass|
              klass.class_eval <<-END
                belongs_to :#{attachment}, :class_name => '::#{attachment.to_s.classify}'
              END
            end
          end

          table_name_prefixes = [table_name_prefix,base_class.name.demodulize.underscore].join
          self::AttributeShadow.set_table_name([table_name_prefixes, '_attribute_shadows', table_name_suffix].join)
          self::AssociationShadow.set_table_name([table_name_prefixes, '_association_shadows', table_name_suffix].join)
        end

        module ShadowInstanceMethods
          def store_updated_association(association_shadow)
            self.class::AssociationShadow.create! association_shadow
          end

          def store_updated_attributes
            unless @updated_attributes.empty? or self.new_record?
              attribute_shadow = {
                self.class.to_s.foreign_key => self.id,
                :updated_attributes => @updated_attributes,
              }

              if self.class.respond_to?(:version_column)
                attribute_shadow[:version] = self.send(self.class.send(:version_column))
              end

              self.class.shadowed_attachments.each do |attachment|
                if (attached_object = self.send(attachment)).nil? or attached_object.new_record?
                  raise ShadowAttachmentError.new(self.class.to_s, attachment)
                else
                  attribute_shadow.update("#{attachment}_id".to_sym => attached_object.id)
                end
              end

              self.class::AttributeShadow.create! attribute_shadow
            end
          end

          protected
          def determine_updated_attributes
            @attributes_before_save = self.new_record? ? {} : self.class.find(self.id, {
              :select => self.class.shadowed_attributes.join(',')
            }).attributes.dup

            @updated_attributes = @attributes_before_save.keys.select do |name|
              (@attributes_before_save[name].to_s != self[name].to_s)
            end
          end
        end

        module ShadowClassMethods
          def create_attribute_shadow_table(options = {})
            table_name = base_class.name.demodulize.underscore

            shadow_table_name = [
              table_name_prefix,
              table_name,
              '_attribute_shadows',
              table_name_suffix
            ].join

            attach_fields = [options.delete(:attach)].flatten.compact

            ActiveRecord::Base.connection.create_table shadow_table_name, :force => true do |t|
              t.text     "updated_attributes"
              t.integer  "version"
              t.datetime "created_at"
              t.datetime "updated_at"

              t.integer table_name.to_s.foreign_key

              attach_fields.each do |field|
                t.integer field.to_s.foreign_key
              end
            end
          end

          def create_association_shadow_table(options = {})
            table_name = base_class.name.demodulize.underscore

            shadow_table_name = [
              table_name_prefix,
              table_name,
              '_association_shadows',
              table_name_suffix
            ].join

            attach_fields = [options.delete(:attach)].flatten.compact

            ActiveRecord::Base.connection.create_table shadow_table_name, :force => true do |t|
              t.string   "association"
              t.string   "action"
              t.integer  "record_id"
              t.integer  "record_version"
              t.datetime "created_at"
              t.datetime "updated_at"

              t.integer table_name.to_s.foreign_key

              attach_fields.each do |field|
                t.integer field.to_s.foreign_key
              end
            end
          end

          def create_shadow_tables(options = {})
            create_attribute_shadow_table(options)
            create_association_shadow_table(options)
          end

          def drop_shadow_tables
            table_name = base_class.name.demodulize.underscore

            association_shadow_table_name = [
              table_name_prefix,
              table_name,
              '_association_shadows',
              table_name_suffix
            ].join

            ActiveRecord::Base.connection.drop_table association_shadow_table_name

            attribute_shadow_table_name = [
              table_name_prefix,
              table_name,
              '_attribute_shadows',
              table_name_suffix
            ].join

            ActiveRecord::Base.connection.drop_table attribute_shadow_table_name
          end

          protected
          def build_instance_attachments
            self.shadowed_attachments.each do |attachment|
              unless [attachment.to_s, "#{attachment}="].all? {|method| self.instance_methods.include?(method)}
                self.class_eval do
                  attr_accessor attachment
                end
              end
            end
          end

          def build_association_attachments
            self.shadowed_associations.each do |name|
              reflection = self.reflect_on_association name

              reflection_class = reflection.options.key?(:class_name) ? 
                reflection.options[:class_name].to_s.constantize : reflection.name.to_s.classify.constantize

              self.shadowed_attachments.each do |attachment|
                unless [attachment.to_s, "#{attachment}="].all? {|method| reflection_class.instance_methods.include?(method)}
                  reflection_class.class_eval do
                    attr_accessor attachment
                  end
                end
              end
            end
          end

          def build_association_callbacks
            self.shadowed_associations.each do |name|
              add_association_callbacks(name, {:after_add => :added, :after_remove => :removed}.inject({}) do |hsh,pair|
                hsh.update({
                  pair.first => Proc.new do |owner,target|
                    unless target.new_record?
                      association_shadow = {
                        :association => name,
                        owner.class.to_s.foreign_key => owner.id,
                        :record_id => target.id,
                        :action => pair.last
                      }

                      owner.class.shadowed_attachments.each do |attachment|
                        if (attached_object = target.send(attachment)).nil? or attached_object.new_record?
                          raise ShadowAttachmentError.new(target.class.to_s, attachment)
                        else
                          association_shadow.update(attachment.to_s.classify.foreign_key.to_sym => attached_object.id)
                        end
                      end

                      if target.class.respond_to?(:version_column)
                        association_shadow[:record_version] = target.send(target.class.send(:version_column))
                      end

                      owner.updated_associations = [owner.updated_associations].flatten.compact
                      owner.updated_associations << association_shadow

                      owner.store_updated_association association_shadow
                    end
                  end
                })
              end)
            end
          end
        end
      end
    end
  end
end