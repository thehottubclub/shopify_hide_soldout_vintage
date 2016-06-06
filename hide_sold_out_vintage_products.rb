require 'json'
require 'httparty'
require 'pry'
require 'shopify_api'
require 'yaml'

@outcomes = {
  errors: [],
  skipped: [],
  skipped_because_no_inventory_tracking: [],
  skipped_because_multiple_variants: [],
  skipped_because_not_sold_out: [],
  skipped_because_product_not_vintage: [],
  product_is_already_hidden: [],
  successfully_hid_product: [],
  unable_to_hide_product: [],
  responses: []
}

#Load secrets from yaml file & set data values to use
data = YAML::load( File.open( 'config/secrets.yml' ) )
SECURE_URL_BASE = data['url_base']
API_DOMAIN = data['api_domain']

#Constants
DIVIDER = '------------------------------------------'
DELAY_BETWEEN_REQUESTS = 0.11
NET_INTERFACE = HTTParty
STARTPAGE = 1
ENDPAGE = 100

def main
  puts "starting at #{Time.now}"

  if ARGV[0] =~ /product_id=/
    do_product_by_id(ARGV[0].scan(/product_id=(\d+)/).first.first)
  elsif ARGV[0] =~ /\d+/ && ARGV[1] =~ /\d+/
    startpage = ARGV[0].to_i
    endpage = ARGV[1].to_i
    do_page_range(startpage, endpage)
  else
    do_page_range(STARTPAGE, ENDPAGE)
  end

  puts "finished at #{Time.now}"

  File.open(filename, 'w') do |file|
    file.write @outcomes.to_json
  end

  @outcomes.each_pair do |k,v|
    puts "#{k}: #{v.size}"
  end
end

def filename
  "data/hide_sold_out_vintage_products_#{Time.now.strftime("%Y-%m-%d_%k%M%S")}.json"
end

def do_page_range(startpage, endpage)
  (startpage .. endpage).to_a.each do |current_page|
    do_page(current_page)
  end
end

def do_page(page_number)
  puts "Starting page #{page_number}"

  products = get_products(page_number)

  # counter = 0
  products.each do |product|
    @product_id = product['id']
    do_product(product)
  end

  puts "Finished page #{page_number}"
end

def get_products(page_number)
  response = secure_get("/products.json?page=#{page_number}")

  JSON.parse(response.body)['products']
end

def get_product(id)
  JSON.parse( secure_get("/products/#{id}.json").body )['product']
end

def do_product_by_id(id)
  do_product(get_product(id))
end

def do_product(product)
  begin
    puts DIVIDER
    old_tags = product['tags'].split(', ')
    number_vars = product['variants'].count
    inventory_management = product['variants'].first['inventory_management']
    inventory_quantity = product['variants'].first['inventory_quantity']

    if( should_skip_based_on?(old_tags, inventory_quantity, number_vars, inventory_management) )
      skip(product)
    else
      if is_hidden?(product)
        @outcomes[:product_is_already_hidden].push @product_id
        puts "Vintage Product is already hidden"
      else
        hide_product(product)
      end
    end
  rescue Exception => e
    @outcomes[:errors].push @product_id
    puts "error on product #{product['id']}: #{e.message}"
    puts e.backtrace.join("\n")
    raise e
  end
end

def should_skip_based_on?(old_tags, inventory_quantity, number_vars, inventory_management)
  if old_tags.include?('vintage') or old_tags.include?('Vintage')
    if inventory_management == nil
      @outcomes[:skipped_because_no_inventory_tracking].push @product_id
      puts "Skipped because item's inventory is not tracked"
      return true
    elsif inventory_quantity == 0
      if number_vars > 1
        @outcomes[:skipped_because_multiple_variants].push @product_id
        puts "!!**Multiple Variant Vintage Item, Won't Hide Ususally**!!"
        return true
      end

      return false
    else
      @outcomes[:skipped_because_not_sold_out].push @product_id
      puts "skipped because item is not soldout"
      return true
    end
  else
    @outcomes[:skipped_because_product_not_vintage].push @product_id
    puts "skipping because product is not vintage"
    return true
  end
end

def skip(product)
  @outcomes[:skipped].push @product_id
  puts "Skipping product #{product['id']}"
end

def is_hidden?(product)
  if product['published_at'] == nil
    return true
  end
  return false
end

def hide_product(product)
  if result = hide_and_save_product(product)
    @outcomes[:successfully_hid_product].push @product_id
    puts "Hid product #{product['id']}"
  else
    @outcomes[:unable_to_hide_product].push @product_id
    puts "Unable to hide product #{product['id']}:  #{result.body}"
  end

end

def hide_and_save_product(product)
  secure_put(
  "/products/#{product['id']}.json",
  {product: {id: product['id'], published: false}}
  )
end

def secure_get(relative_url)
  sleep DELAY_BETWEEN_REQUESTS
  url = SECURE_URL_BASE + relative_url
  result = NET_INTERFACE.get(url)
end

def secure_put(relative_url, params)
  sleep DELAY_BETWEEN_REQUESTS

  url = SECURE_URL_BASE + relative_url

  result = NET_INTERFACE.put(url, body: params)

  @outcomes[:responses].push({
    method: 'put', requested_url: url, body: result.body, code: result.code
    })
  end

  def put(url, params)
    NET_INTERFACE.put(url, query: params)
  end

  main
