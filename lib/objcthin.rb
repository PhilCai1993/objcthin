require "objcthin/version"
require 'thor'
require 'rainbow'
require 'pathname'
require 'singleton'

module Objcthin
  class Command < Thor
    desc 'findsel','find unused method sel'
    method_option :prefix, :default => '', :type => :string, :desc => 'the class prefix you want find'
    def findsel(path)
      Imp::UnusedSel.instance.find_unused_sel(path, options[:prefix])
    end

    desc 'findclass', 'find unused class list'
    method_option :prefix, :default => '', :type => :string, :desc => 'the class prefix you want find'
    def findclass(path)
      Imp::UnusedClass.instance.find_unused_class(path, options[:prefix])
    end

    desc'version','print version'
    def version
      puts Rainbow(Objcthin::VERSION).green
    end
  end
end

module Imp
  class UnusedSel

    include Singleton

    def find_unused_sel(path, prefix)
      check_file_type(path)
      all_sels = find_impl_methods(path)
      used_sel = reference_selectors(path)

      unused_sel = []

      all_sels.each do |sel,class_and_sels|
        unless used_sel.include?(sel)
          unused_sel += class_and_sels
        end
      end

      puts Rainbow('below selector is unused:').red
      if prefix
        unused_sel.select! do |classname_selector|
          current_prefix = classname_selector.byteslice(2, prefix.length)
          current_prefix == prefix
        end
      end

      puts unused_sel
    end

    def check_file_type(path)
      pathname = Pathname.new(path)
      unless pathname.exist?
        raise "#{path} not exit!"
      end

      cmd = "/usr/bin/file -b #{path}"
      output = `#{cmd}`

      unless output.include?('Mach-O')
        raise 'input file not mach-o file type'
      end
      puts Rainbow('will begin process...').green
      pathname
    end

    def find_impl_methods(path)
      apple_protocols = [
          'tableView:canEditRowAtIndexPath:',
          'commitEditingStyle:forRowAtIndexPath:',
          'tableView:viewForHeaderInSection:',
          'tableView:cellForRowAtIndexPath:',
          'tableView:canPerformAction:forRowAtIndexPath:withSender:',
          'tableView:performAction:forRowAtIndexPath:withSender:',
          'tableView:accessoryButtonTappedForRowWithIndexPath:',
          'tableView:willDisplayCell:forRowAtIndexPath:',
          'tableView:commitEditingStyle:forRowAtIndexPath:',
          'tableView:didEndDisplayingCell:forRowAtIndexPath:',
          'tableView:didEndDisplayingHeaderView:forSection:',
          'tableView:heightForFooterInSection:',
          'tableView:shouldHighlightRowAtIndexPath:',
          'tableView:shouldShowMenuForRowAtIndexPath:',
          'tableView:viewForFooterInSection:',
          'tableView:willDisplayHeaderView:forSection:',
          'tableView:willSelectRowAtIndexPath:',
          'willMoveToSuperview:',
          'scrollViewDidEndScrollingAnimation:',
          'scrollViewDidZoom',
          'scrollViewWillEndDragging:withVelocity:targetContentOffset:',
          'searchBarTextDidEndEditing:',
          'searchBar:selectedScopeButtonIndexDidChange:',
          'shouldInvalidateLayoutForBoundsChange:',
          'textFieldShouldReturn:',
          'numberOfSectionsInTableView:',
          'actionSheet:willDismissWithButtonIndex:',
          'gestureRecognizer:shouldReceiveTouch:',
          'gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:',
          'gestureRecognizer:shouldReceiveTouch:',
          'imagePickerController:didFinishPickingMediaWithInfo:',
          'imagePickerControllerDidCancel:',
          'animateTransition:',
          'animationControllerForDismissedController:',
          'animationControllerForPresentedController:presentingController:sourceController:',
          'navigationController:animationControllerForOperation:fromViewController:toViewController:',
          'navigationController:interactionControllerForAnimationController:',
          'alertView:didDismissWithButtonIndex:',
          'URLSession:didBecomeInvalidWithError:',
          'setDownloadTaskDidResumeBlock:',
          'tabBarController:didSelectViewController:',
          'tabBarController:shouldSelectViewController:',
          'applicationDidReceiveMemoryWarning:',
          'application:didRegisterForRemoteNotificationsWithDeviceToken:',
          'application:didFailToRegisterForRemoteNotificationsWithError:',
          'application:didReceiveRemoteNotification:fetchCompletionHandler:',
          'application:didRegisterUserNotificationSettings:',
          'application:performActionForShortcutItem:completionHandler:',
          'application:continueUserActivity:restorationHandler:'].freeze

      # imp -[class sel]

      sub_patten = /[+|-]\[.+\s(.+)\]/
      patten = /\s*imp\s*(#{sub_patten})/
      sel_set_patten = /set[A-Z].*:$/
      sel_get_patten = /is[A-Z].*/

      output = `/usr/bin/otool -oV #{path}`

      imp = {}

      output.each_line do |line|
        patten.match(line) do |m|
          sub = sub_patten.match(m[0]) do |subm|
            class_and_sel = subm[0]
            sel = subm[1]

            next if sel.start_with?('.')
            next if apple_protocols.include?(sel)
            next if sel_set_patten.match?(sel)
            next if sel_get_patten.match?(sel)

            if imp.has_key?(sel)
              imp[sel] << class_and_sel
            else
              imp[sel] = [class_and_sel]
            end
          end
        end
      end

      imp.sort
    end

    def reference_selectors(path)
      patten = /__TEXT:__objc_methname:(.+)/
      output = `/usr/bin/otool -v -s __DATA __objc_selrefs #{path}`

      sels = []
      output.each_line do |line|
        patten.match(line) do |m|
          sels << m[1]
        end
      end

      sels
    end
  end
end


module Imp
  class UnusedClass

    include Singleton

    def find_unused_class(path, prefix)
      check_file_type(path)
      result = split_segment_and_find(path, prefix)
      puts result.values
    end

    def check_file_type(path)
      pathname = Pathname.new(path)
      unless pathname.exist?
        raise "#{path} not exit!"
      end

      cmd = "/usr/bin/file -b #{path}"
      output = `#{cmd}`

      unless output.include?('Mach-O')
        raise 'input file not mach-o file type'
      end
      #puts Rainbow('will begin process...').green
      pathname
    end

    def split_segment_and_find(path, prefix)

      arch_command = "lipo -info #{path}"
      arch_output = `#{arch_command}`

      arch = 'arm64'
      if arch_output.include? 'arm64'
        arch = 'arm64'
      elsif arch_output.include? 'x86_64'
        arch = 'x86_64'
      elsif arch_output.include? 'armv7'
        arch = 'armv7'
      end

      command = "/usr/bin/otool -arch #{arch}  -V -o #{path}"
      output = `#{command}`

      class_list_identifier = 'Contents of (__DATA,__objc_classlist) section'
      class_refs_identifier = 'Contents of (__DATA,__objc_classrefs) section'

      unless output.include? class_list_identifier
        raise Rainbow('only support iphone target, please use iphone build...').red
      end

      patten = /Contents of \(.*\) section/

      name_patten_string = '.*'
      unless prefix.empty?
        name_patten_string = "#{prefix}.*"
      end

      vmaddress_to_class_name_patten = /^(\d*\w*)\s(0x\d*\w*)\s_OBJC_CLASS_\$_(#{name_patten_string})/

      class_list = []
      class_refs = []
      used_vmaddress_to_class_name_hash = {}

      can_add_to_list = false
      can_add_to_refs = false

      output.each_line do |line|
        if patten.match?(line)
          if line.include? class_list_identifier
            can_add_to_list = true
            next
          elsif line.include? class_refs_identifier
            can_add_to_list = false
            can_add_to_refs = true
          else
            break
          end
        end

        if can_add_to_list
          class_list << line
        end

        if can_add_to_refs && line
          vmaddress_to_class_name_patten.match(line) do |m|
            unless used_vmaddress_to_class_name_hash[m[2]]
              used_vmaddress_to_class_name_hash[m[2]] = m[3]
            end
          end
        end
      end

      # remove cocoapods class
      podsd_dummy = 'PodsDummy'

      vmaddress_to_class_name_hash = {}
      class_list.each do |line|
        next if line.include? podsd_dummy
        vmaddress_to_class_name_patten.match(line) do |m|
          vmaddress_to_class_name_hash[m[2]] = m[3]
        end
      end

      result = vmaddress_to_class_name_hash
      vmaddress_to_class_name_hash.each do |key, value|
        if used_vmaddress_to_class_name_hash.keys.include?(key)
          result.delete(key)
        end
      end

      result
    end
  end
  end
