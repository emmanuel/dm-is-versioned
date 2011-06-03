module DataMapper
  module Is
    ##
    # = Is Versioned
    # The Versioned module will configure a model to be versioned.
    #
    # The is-versioned plugin functions differently from other versioning
    # solutions (such as acts_as_versioned), but can be configured to
    # function like it if you so desire.
    #
    # The biggest difference is that there is not an incrementing 'version'
    # field, but rather, any field of your choosing which will be unique
    # on update.
    #
    # == Setup
    # For simplicity, I will assume that you have loaded dm-timestamps to
    # automatically update your :updated_at field. See versioned_spec for
    # and example of updating the versioned field yourself.
    #
    #   class Story
    #     include DataMapper::Resource
    #     property :id, Serial
    #     property :title, String
    #     property :updated_at, DateTime
    #
    #     is_versioned :on => :updated_at
    #   end
    #
    # == Auto Upgrading and Auto Migrating
    #
    #   Story.auto_migrate! # => will run auto_migrate! on Story::Version, too
    #   Story.auto_upgrade! # => will run auto_upgrade! on Story::Version, too
    #
    # == Usage
    #
    #   story = Story.get(1)
    #   story.title = "New Title"
    #   story.save # => Saves this story and creates a new version with the
    #              #    original values.
    #   story.versions.size # => 1
    #
    #   story.title = "A Different New Title"
    #   story.save
    #   story.versions.size # => 2
    #
    # TODO: enable replacing a current version with an old version.
    module Versioned
      def is_versioned(options = {})
        assert_kind_of "options[:on]", options[:on], Symbol

        @versioned_on = on = options[:on]
        class << self
          attr_reader :versioned_on
        end

        # TODO: clean this up. there ought to be some way to get the original
        # attributes after the data-store has confirmed the save
        before :save do
          @_previous_attributes = original_attributes.dup
        end

        after :create, :record_create

        extend Migration if respond_to?(:auto_migrate!)
        extend ClassMethods
        include InstanceMethods
      end

      def self.create_version_model(versioned_model, name = :Version)
        version_property_name = versioned_model.versioned_on
        model = DataMapper::Model.new(name, versioned_model)

        versioned_model.properties.each do |property|
          versioned_on_property = property.name == version_property_name
          # next unless property.key? || versioned_on_property

          type =
            case property
            when DataMapper::Property::Discriminator then Class
            when DataMapper::Property::Serial        then Integer
            else property.class
            end

          options = property.options.merge(:key => versioned_on_property)
          options[:key] = true if options.delete(:serial)

          model.property(property.name, type, options)
        end

        model.property(:resource_attributes, DataMapper::Property::Text)
        model.timestamps :created_at if defined?(DataMapper::Timestamps)

        model
      end

      module ClassMethods
        # Don't create the version model until the constant is accessed. This
        # allows property definitions to occur after the is_versioned call.
        # 
        # @api private
        def const_missing(name)
          if name == :Version
            DataMapper::Is::Versioned.create_version_model(self, name)
          else
            super
          end
        end
      end # ClassMethods

      module InstanceMethods
        ##
        # Returns a collection of other versions of this resource.
        # The versions are related on the models keys, and ordered
        # by the version field.
        #
        # --
        # @return <Collection>
        def versions
          version_model = model.const_get(:Version)
          query = Hash[ model.key.zip(key).map { |p, v| [ p.name, v ] } ]
          query.merge(:order => version_model.key.map { |k| k.name.desc })
          version_model.all(query)
        end

      private

        def record_event(event)
          if clean? && @_previous_attributes.key?(model.versioned_on)
            snapshot = attributes.merge(@_previous_attributes)
            raise "snapshot: #{snapshot.inspect}"
            version_attributes = self.version_attributes.merge({
              :event => event,
              :resource_attributes => snapshot
            }).merge(Hash[model.key.map { |p| p.name }.zip(key)])
            version = model::Version.create(version_attributes)
            p [version_attributes, version].inspect
            @_previous_attributes = {}
          end
        end

        def record_create
          record_event(:create)
        end

        # attributes that will be set on new versions of this Resource when created
        def new_version_attributes
          {}
        end
      end # InstanceMethods

      module Migration

        def auto_migrate!(repository_name = self.repository_name)
          super
          self::Version.auto_migrate!
        end

        def auto_upgrade!(repository_name = self.repository_name)
          super
          self::Version.auto_upgrade!
        end

      end # Migration

    end # Versioned
  end # Is
end # DataMapper
