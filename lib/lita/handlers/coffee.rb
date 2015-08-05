module Lita
  module Handlers
    class Coffee < Handler
      # TODO: money - probably in a separate handler and maybe it already exists??

      # Dependencies
      require 'json'

      # Configuration
      # default_group - the name of the default group in which users will order a coffee
      # default_coffee - the coffee we will order if users don't specify what they would like
      config :default_group, type: String, default: 'coffee-lovers'
      config :default_coffee, type: String, default: 'Single origin espresso'
      config :default_timeout, type: Integer, default: 604800
      on :loaded, :set_constants

      def set_constants(payload)
        @@DEFAULT_GROUP   = config.default_group
        @@DEFAULT_COFFEE  = config.default_coffee
        @@DEFAULT_GROUP_TIMEOUT = config.default_timeout
      end

      # ---------------
      # Nice new routes
      # ---------------

      # Welcome new users
      route(
        /coffee/i,
        :init_user,
      )

      # Order a coffee
      route(
        /^\s*\(?coffee\)?\s+\+\s*(\S.*)?$/i,
        :get_me_a_coffee,
        help: {
          'coffee +'                    => "Order a coffee",
        }
      )

      # Cancel your order
      route(
        /^\s*\(?coffee\)?\s+\-c\s*$/i,
        :cancel_order,
        help: {
          'coffee -c'                   => "Cancel your order",
        }
      )

      # List orders
      route(
        /^\s*\(?coffee\)?\s*$/i,
        :list_orders,
        help: {
          'coffee'                      => "List the orders for your group",
        }
      )

      # Display profile informatino
      route(
        /^\s*\(?coffee\)?\s+\-i\s*$/i,
        :display_profile,
        help: {
          'coffee -i'                   => "Display your profile",
        }
      )

      # Set preferences
      route(
        /^\s*\(?coffee\)?\s+\-s\s+(.*)$/i,
        :set_prefs,
        help: {
          'coffee -s Colombian Filter'  => "Set your coffee preference",
        }
      )

      # Set group
      route(
        /^\s*\(?coffee\)?\s+\-g\s+(.*)$/i,
        :set_group,
        help: {
          'coffee -g Cool Kids'  => "Change your group",
        }
      )

      # Buy coffees
      route(
        /^\s*\(?coffee\)?\s+\-b\s*(.*)$/i,
        :buy_coffees,
        help: {
          'coffee -b You owe me one!'   => "Buy coffee for your group, clear the orders and send a message to each coffee drinker",
        }
      )

      # Display system settings
      route(
        /^\s*\(?coffee\)?\s+\-t\s*(.*)$/i,
        :system_settings,
        help: {
          'coffee -t'                   => "Display system settings",
        }
      )

      # Delete me
      route(
        /^\s*\(?coffee\)?\s+\-d\s*(.*)$/i,
        :delete_me,
        help: {
          'coffee -d'                   => "Delete you from the coffee system",
        }
      )

      # List all groups
      route(
        /^\s*\(?coffee\)?\s+\-l\s*(.*)$/i,
        :list_groups,
        help: {
          'coffee -l'                   => "List the available coffee groups",
        }
      )

      # Setup new users
      def init_user(response)
        response.reply("Welcome to coffee! You have been added to the #{@@DEFAULT_GROUP} group with an order of #{@@DEFAULT_COFFEE}. Type help coffee for help.") if initialize_user_redis(response.user.name) == :new_user
      end

      # Order coffee
      def get_me_a_coffee(response)
        group = response.matches[0][0].strip rescue get_group(response.user.name)
        orders = (get_orders(group) + [response.user.name]).uniq
        result = redis.set("orders:#{group}",orders.to_json)
        set_timeout(group)
        if result == "OK"
          response.reply("Ordered you a coffee from #{group}")
        else
          response.reply("(sadpanda) Failed to order your coffee for some reason: #{result.inspect}")
        end
      end

      # Cancel coffee order
      def cancel_order(response)
        group = get_group(response.user.name)
        orders = get_orders(group)
        orders.delete(response.user.name)
        result = redis.set("orders:#{group}",orders.to_json)
        set_timeout(group)
        if result == "OK"
          response.reply("Cancelled your coffee")
        else
          response.reply("(sadpanda) Failed to cancel your coffee for some reason: #{result.inspect}")
        end
      end

      # List the coffee orders for your group
      def list_orders(response)
        group = get_group(response.user.name)
        response.reply("Current orders for #{group}:-\n--")
        get_orders(group).each do |order|
          response.reply("#{order}: #{get_coffee(order)}")
        end
      end

      # Display profile
      def display_profile(response)
        settings = get_settings(response.user.name)
        response.reply("Your current coffee is #{settings['coffee']}. You are in the #{settings['group']} group.")
      end

      # Set coffee preference
      # TODO: a single method to update user info
      def set_prefs(response)
        preference = response.matches[0][0].strip rescue nil
        result = update_user_coffee(response.user.name,preference)
        if result == "OK"
          response.reply("Coffee set to #{preference}")
        else
          response.reply("(sadpanda) Failed to set your coffee for some reason: #{result.inspect}")
        end
      end

      # Set coffee group
      # TODO: merge with coffee preference
      def set_group(response)
        preference = response.matches[0][0].strip rescue nil
        result = set_coffee_group(response.user.name,preference)
        if result == "OK"
          response.reply("Group set to #{preference}")
        else
          response.reply("(sadpanda) Failed to set your coffee group for some reason: #{result.inspect}")
        end
      end

      # Buy all the coffee for your group
      def buy_coffees(response)
        puts "Running buy_coffees"
        group = get_group(response.user.name)
        message = response.matches[0][0].strip rescue nil
        response.reply("Thanks for ordering the coffee for #{group}!\n--")
        get_orders(group).each do |order|
          response.reply("#{order}: #{get_coffee(order)}")
          send_coffee_message(order,response.user.name,message) unless order == response.user.name
        end
        result = clear_orders(group)
        if result == "OK"
          response.reply("Cleared all orders for #{group}")
        else
          response.reply("(sadpanda) Failed to clear the orders for some reason: #{result.inspect}")
        end
      end

      # Display the system settings
      def system_settings(response)
        response.reply("Default coffee: #{@@DEFAULT_COFFEE}, Default group: #{@@DEFAULT_GROUP}")
      end

      # Delete a user
      def delete_me(response)
        result = redis.del("settings:#{response.user.name}")
        if result == 1
          response.reply("You have been deleted from coffee")
        else
          response.reply("(sadpanda) Failed to delete you from coffee for some reason: #{result.inspect}")
        end
      end

      # List groups
      def list_groups(response)
        groups = redis.keys('orders:*')
        response.reply("The following groups are active:-\n--\n#{groups.map{|g| g.split(':')[1]}.join("\n")}")
      end

      #######
      private
      #######

      def initialize_user_redis(user)
        if redis.get("settings:#{user}").nil?
          redis.set("settings:#{user}",{group: @@DEFAULT_GROUP, coffee: @@DEFAULT_COFFEE}.to_json)
          return :new_user
        else
          return :existing_user
        end
      end

      def get_settings(user)
        JSON.parse(redis.get("settings:#{user}")) rescue {group: @@DEFAULT_GROUP, coffee: @@DEFAULT_COFFEE}
      end

      def get_orders(group)
        set_timeout(group)
        JSON.parse(redis.get("orders:#{group}")) rescue []
      end

      def get_coffee(user)
        JSON.parse(redis.get("settings:#{user}"))['coffee'] rescue @@DEFAULT_COFFEE
      end

      def get_group(user)
        JSON.parse(redis.get("settings:#{user}"))['group'] rescue @@DEFAULT_GROUP
      end

      def update_user_coffee(user,coffee)
        my_settings = get_settings(user)
        my_settings[:coffee] = coffee
        redis.set("settings:#{user}",my_settings.to_json)
      end

      def set_coffee_group(user,group)
        my_settings = get_settings(user)
        my_settings[:group] = group
        redis.set("settings:#{user}",my_settings.to_json)
      end

      def clear_orders(group)
        set_timeout(group)
        redis.set("orders:#{group}",[])
      end

      def send_coffee_message(user,purchaser,message)
        myuser = Lita::User.find_by_name(user)
        msg = Lita::Message.new(robot,'',Lita::Source.new(user: myuser))
        msg.reply("#{purchaser} has bought you a coffee!")
        msg.reply(message) # what happens if message is nil?
      rescue => e
        Lita.logger.error("Coffee#send_coffee_message raised #{e.class}: #{e.message}\n#{e.backtrace}")
      end

      def set_timeout(group)
        redis.expire("orders:#{group}",@@DEFAULT_GROUP_TIMEOUT)
      end


    end

    Lita.register_handler(Coffee)
  end
end
