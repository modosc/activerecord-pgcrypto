# Activerecord::Pgcrypto

Enable transparent encryption / decryption for ActiveRecord using [pgcrypto](http://www.postgresql.org/docs/current/static/pgcrypto.html)


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activerecord-pgcrypto', require: 'active_record/pgcrypto'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install activerecord-pgcrypto

## Setup
If you've got a `Foo` model that you want to add an encrypted `bar` attribute to:
1. Create a new migration:

```
  def change
    enable_extension "pgcrypto"
    add_column :foos, :encrypted_bar, :string
    # you only need the :hashed_ column if you want to make your model searchable
    add_column :foos, :hashed_bar, :string
  end
```  
2. Create and export a public / private key pair

```
$ gpg --gen-key
$ gpg --output your@email.address.pub.gpg --armor --export your@email.address
$ gpg --output your@email.address.priv.gpg --armor --export-secret-key your@email.address
```

3. If your attribute needs to be searchable create a salt in `postgresql`:

```
$ psql postgres
instamotor_dev=# select gen_salt('bf') \g
           gen_salt
-------------------------------
 $2a$31$jMwo4bUG8hliR5QfSqLv.O
```

3. create a new initializer in `config/initializers/activerecord_pgcrypto.rb`:

```
ActiveRecord::Pgcrypto.configure do |config|
  # public_key - required
  # the contents of your public key.
  # defaults to the value of ENV['PGCRYPTO_PUBLIC_KEY']
  config.public_key = File.read 'path/to/your/public/key'

  # private_key - required
  # the contents of your private key.
  # defaults to the value of ENV['PGCRYPTO_PRIVATE_KEY']
  config.private_key = File.read 'path/to/your/private/key'

  # salt - required to make a model searchable
  # salt to use for searching, see below for more discussion
  # defaults to ENV['PGCRYPTO_SALT']

  # private_key_password - optional
  # the password for your private key (if you set one)
  # defaults to the value of ENV['PGCRYPTO_PRIVATE_KEY_PASSWORD']


end
```

4. Add to your model:

```
class Foo < ActiveRecord::Base
  include ActiveRecord::Pgcrypto
  has_encrypted_attributes :bar
  # ...
end
```

5. Now your model will transparently save and retrieve encrypted values:

```
> foo = Foo.create! bar: "something secret"
> foo.bar
=> "something secret"
> foo.encrypted_bar
=> "c1c04c031227ab19d18859520107fc0c01fde099a4efbc73134847e76163a44c5c3d6910a5ff99373a06b451e46eb75345ce0b35ba883959b7b496895f6ea9ed7e41344b9d771c7feabc0e410ba4fa8788185f1a0b2cc778ee01e51a0549624288e7af1a5f4c5602e45600e447449f9ed9c74d7a35b2c5729252d957328e7c4eaa046fcd3c6069d59742edea636cb9a7909736f42faa38485d6ce9bb5791bee4ba3749aec2203ba6c28a21c039d6161c33b54c9451893254a89860fb81706fd7f0f4f521d2c3e54bf0a27666bbcadb2514dd3712de9c07896c7be950bfb5e1a61f3879e1dd5bfea4590e5609b7677d9b6f81fc6d2d7ebdee3c275185e942183d51811d4eb586c29c41835256699e09d27001953979efee6343b0cbdbd500bcdc1070337a3670cbcf45fd0064b5df907a0dd6a19f32521a5281f0a06cf43bf9f3972c3c0c0c7b7511958f3bec6deaa252bfbf9ea4ec1f38396f989fbbe6f91d506450f7828b09e2b077dc264c86919584f3adc14b71cb3cde2897b28123bd09ac32"
 > # if you added the hashed_ attribute
 > foo.hashed_bar
 => "$2a$06$kE5K8B4EiFQ3CHnSn4Mw9.vJeDt5Auhn4e/pq8rqN"
```

## Logging
Logging is filtered to avoid leaking secrets:
```
D, [2016-05-19T09:49:41.370025 #20166] DEBUG -- :   decrypt (0.1ms)  SELECT pgp_pub_decrypt(decode($1, 'hex'), dearmor($2), $3) AS decrypt  [[nil, "[FILTERED]"], [nil, "[FILTERED]"], [nil, "[FILTERED]"]]
D, [2016-05-19T09:49:41.374493 #20166] DEBUG -- :   crypt (4.2ms)  SELECT crypt($1, gen_salt('bf')) AS crypt  [[nil, "[FILTERED]"]]
D, [2016-05-19T09:49:41.375135 #20166] DEBUG -- :   encrypt (0.3ms)  SELECT encode(pgp_pub_encrypt($1, dearmor($2), 'compress-algo=2,compress-level=9,cipher-algo=aes256'), 'hex') AS encrypt  [[nil, "[FILTERED]"], [nil, "[FILTERED]"]]
```

Any encrypted attributes are also automatically added to `Rails.configuration.filter_parameters` to avoid leaking them in request logs.

## Searching

In order for search to work you must add the `hashed_*` attribute in your migration. You also need to have a `salt` specified in your configuration. Searching is accomplished with special search methods. Currently the standard ActiveRecord methods don't work so you can't do this:
```
> Foo.where(bar: 'asdfasdf')
```

Instead (for now) you have to do:

```
> Foo.find_by_bar("asdfasdf")
```

This method is chainable so you can use other ActiveRecord query methods:
```
> Foo.find_by_bar("asdfasdf").where(baz: 123).limit(1)
```

## Security
All crypto methods come from [pgcrypto](http://www.postgresql.org/docs/current/static/pgcrypto.html).

Encryption / decryption is done using `pgp_pub_encrypt()` and `pgp_pub_decrypt()`. This means it's possible to grant a service write-only access to encrypted values by providing it access to the database but not providing the private key. The options used are:

```
compress-algo=2, compress-level=9, cipher-algo=aes256
```

See [here](http://www.postgresql.org/docs/current/static/pgcrypto.html#AEN172363) for more info. This will probably become confirable in the fugure.

Hashing is done with the `crypt()` method using the `bf` algorithm. The default iteration count of 6 is used for `bf`, see [this table](http://www.postgresql.org/docs/current/static/pgcrypto.html#PGCRYPTO-ICFC-TABLE) for more info. This may become a configuration option in the future.

## Roadmap

1. Add a migration generator
2. Make searchability an option rather than a default
3. Figure out the Arel magic so that the standard ActiveRecord query methods work.
4. Look into using [#attribute](http://edgeapi.rubyonrails.org/classes/ActiveRecord/Attributes/ClassMethods.html#method-i-attribute) instead of the existing `define_method` solution
5. Break out `pgcrypto` methods into a separate module so they can be used outside of this code.
6. Add optional compression inside of Rails-land rather than depending on the inefficient `compress-level` setting.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/activerecord-pgcrypto.
