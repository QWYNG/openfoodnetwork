require 'spree/core/controller_helpers/order_decorator'

class CartController < BaseController
  before_filter :check_authorization

  def populate
    # Without intervention, the Spree::Adjustment#update_adjustable callback is called many times
    # during cart population, for both taxation and enterprise fees. This operation triggers a
    # costly Spree::Order#update!, which only needs to be run once. We avoid this by disabling
    # callbacks on Spree::Adjustment and then manually invoke Spree::Order#update! on success.
    Spree::Adjustment.without_callbacks do
      cart_service = CartService.new(current_order(true))

      if cart_service.populate(params.slice(:products, :variants, :quantity), true)
        fire_event('spree.cart.add')
        fire_event('spree.order.contents_changed')

        current_order.cap_quantity_at_stock!
        current_order.update!

        variant_ids = variant_ids_in(cart_service.variants_h)

        render json: { error: false,
                       stock_levels: VariantsStockLevels.new.call(current_order, variant_ids) },
               status: :ok
      else
        render json: { error: true }, status: :precondition_failed
      end
    end
    populate_variant_attributes
  end

  def variant_ids_in(variants_h)
    variants_h.map { |v| v[:variant_id].to_i }
  end

  private

  def check_authorization
    session[:access_token] ||= params[:token]
    order = Spree::Order.find_by_number(params[:id]) || current_order

    if order
      authorize! :edit, order, session[:access_token]
    else
      authorize! :create, Spree::Order
    end
  end

  def populate_variant_attributes
    order = current_order.reload

    populate_variant_attributes_from_variant(order) if params.key? :variant_attributes
    populate_variant_attributes_from_product(order) if params.key? :quantity
  end

  def populate_variant_attributes_from_variant(order)
    params[:variant_attributes].each do |variant_id, attributes|
      order.set_variant_attributes(Spree::Variant.find(variant_id), attributes)
    end
  end

  def populate_variant_attributes_from_product(order)
    params[:products].each do |_product_id, variant_id|
      max_quantity = params[:max_quantity].to_i
      order.set_variant_attributes(Spree::Variant.find(variant_id),
                                   max_quantity: max_quantity)
    end
  end
end
