Shadow
======

Provides a history of attribute and association updates for models. This coincides with a versioning system (such as acts_as_versioned). When used in tandem, you get both a history of changes and a history of what changed.

Installation
============

If you are running Rails 2.1 or later, installation is straightforward:

<pre><code>
  $ ./script/plugin install git://github.com/TheBreeze/shadow.git
</code></pre>

Otherwise, the process is a bit more involved, see below:

<pre><code>
  $ cd /path/to/your/rails/app
  $ git clone --depth 1 git://github.com/TheBreeze/shadow.git "./vendor/plugins/shadow/"; rm -rf ./vendor/plugins/shadow/.git
</code></pre>


Example
=======

<pre><code>
  # After creating your migrations (see TODO)

  # In your model

  class Vacation < ActiveRecord::Base
    has_many :photos

    # By default, shadows all :attributes and :associations. Here we're attaching a user, so we know who added a photo.
    shadow :associations => :photos, :attach => :user
  end
</code></pre>

<pre><code>
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
</code></pre>

<pre><code>
  # In your view (displaying the updates in the show action of VacationController)

  &lt;h1&gt;Vacation Updates&lt;/h1&gt;

  &lt;% @vacation.association_updates.each do |update| -%&gt;
    &lt;p&gt;&lt;%= update.user.name %&gt; &lt;%= update.action %&gt; &lt;%= update.record.thumbnail %&gt; to &lt;%= update.association %&gt;&lt;/p&gt;
  &lt;% end -%&gt;
</code></pre>


<pre><code>
  # Example result from view:

  &lt;h1&gt;Vacation Updates&lt;/h1&gt;
  &lt;p&gt;Jordan added [photo thumbnail] to photos&lt;/p&gt;
</code></pre>

Copyright (c) 2008 Jordan Fowler, released under the MIT license, and originally developed for Cinema Treasures, LLC (http://www.cinematreasures.org/).
