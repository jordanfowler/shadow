Shadow
======

Provides a history of attribute and association updates for models. This coincides with a versioning system (such as acts_as_versioned). When used in tandem, you get both a history of changes and a history of what changed.

Example
=======

# After creating your migrations (see TODO)

# In your model

  class Vacation < ActiveRecord::Base
    has_many :photos

    # By default, shadows all :attributes and :associations. Here we're attaching a user, so we know who added a photo.
    shadow :associations => :photos, :attach => :user
  end

# In your controller (here we assume nested under VacationController)

  class PhotosController < ApplicationController
    def create
      @vacation = Vacation.find params[:vacation_id]

      # This is where you attach the :user to the photo. If Photo doesn't have a user attribute or association, shadow
      # will attach an attr_accessor to it and store it with the AssociationShadow record.
      @photo = Photo.new params[:photo].merge(:user => current_user)

      # You must either use the #association<<, #association.push, or #association.create for the shadow to be created.
      if @vacation.photos << @photo
        # success!
      end
    end
  end

# In your view (displaying the updates in the show action of VacationController)

<h1>Vacation Updates</h1>

  <% @vacation.association_updates.each do |update| -%>
    <p><%= update.user.name %> <%= update.action %> <%= update.record.thumbnail %> to <%= update.association %></p>
  <% end -%>

# Example result from view:

<h1>Vacation Updates</h1>

<p>Jordan added [photo thumbnail] to photos</p>



Copyright (c) 2008 Jordan Fowler, released under the MIT license
