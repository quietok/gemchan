require 'yaml'
module Gemchan
    class ChanController
        @@boards = {}
        @@config_path = 'config.yaml'
        @@configurations = Object
        @@allowed_ftypes = ['png','jpeg','gif','webp']

        def self.init
            Board.find_each do |board|
                @@boards[board[:upath]] = board[:id]
            end
            @@configurations = YAML.load(File.read(@@config_path))
            @@configurations[:boards] = @@boards
            @@allowed_ftypes = @@configurations[:allowed_ftypes]
            self.update_conf
        end

        def self.update_conf
            File.open(@@config_path, 'w') do |file|
                file.write(@@configurations.to_yaml)
            end
        end

        def self.configurations
            return YAML.load(File.read(@@config_path))
        end

        def self.create_post(params, is_op=false)
            board = Board.find(params[:board])

            if params[:file] == nil
                filepath = nil
            else
                puts params[:file].inspect()
                filepath = self._handle_file(params[:file][:tempfile],params[:file][:filename])
            end

            post = board.posts.create(name: params[:name], subject: params[:subject], content: params[:content], media: filepath)
            
            unless is_op
                op_post = board.ops.where("post_id = #{params[:op]}")
                begin
                    op_post.touch_all
                rescue
                    op_post.each(&:touch)
                end
                post.op_id = params[:op]
            else
                op_post = board.ops.create(post_id: post[:id])
                post.op_id = post.id
            end
            post.save
        end
        
        def self.delete_post(params)
            for post in params["posts"]
                post = Post.find(post.to_i)
                if post.id == post.op_id

                    #op = Board.find(post.board_id).ops.find_by("post_id = #{post.op_id}")
                    Op.find(post.id).delete
                    posts = Post.where("op_id = #{post.id}")
                    for post in posts
                        post.delete
                    end
                else
                    post.delete
                end
            end
            if params["images"] != nil
                for image in params["images"]
                    puts image
                end
            end
        end

        def self._handle_file(tempfile, filename)
            mtype = MimeMagic.by_magic(File.open(tempfile.path))
            dirp = File.join( "public", "uploads")
            unless @@allowed_ftypes.include? mtype.subtype
                return nil
            end
            md5t = Digest::MD5.file(tempfile.path).hexdigest
            newname = File.join(dirp, "#{md5t}.#{mtype.subtype}")
            thumbname = File.join(dirp, "#{md5t}.thumb.#{mtype.subtype}")
            servename = "/uploads/#{md5t}.#{mtype.subtype}"
            if mtype.mediatype == 'image'
                image = Magick::Image.read(tempfile.path).first
                image.thumbnail(image.columns*(300.0/image.columns), image.rows*(300.0/image.columns)).write(thumbname)
            end
            FileUtils.cp(tempfile.path, newname)

            return servename
        end

        def self.boards_dict
            return @@boards
        end

        def self.update_boards_dict
            Board.find_each do |board|
                @@boards[board[:upath]] = board[:id]
            end
            @@configurations[:boards] = @@boards
            self.update_conf
        end

        def self.createboard(params)
            unless @@boards.has_key? params[:upath] 
                @@boards[params[:upath]] = Board.create(upath: params[:upath], name: params[:name], description: params[:description]).id
            else 
                "board exists"
            end
            self.update_boards_dict
        end

        def self.board_page_data(route)
            page_data = {}
            board_data = {}
            board = Board.find(@@boards[route])
            board_data[:id] = board.id
            board_data[:upath] = board.upath
            board_data[:name] = board.name
            board_data[:description] = board.description
            ops = board.ops.sort_by(&:updated_at).reverse
            for op in ops
                page_data[op.post_id] = board.posts.where("op_id = #{op.post_id}").last(4)
            end
            return board_data, page_data
        end

        def self.number_per_page
            return @@configurations[:per_page].to_i
        end

        def self.thread_page_data(thread, route)
            bid = Gemchan::ChanController::boards_dict[route]
            posts = Post.where("op_id = #{thread}").sort_by(&:created_at)
            return bid, posts
        end

    end
end