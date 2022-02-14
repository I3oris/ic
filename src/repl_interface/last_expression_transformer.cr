module Crystal
  class LastExpressionTransformer < Transformer
    def transform(node : Expressions)
      transform(node.expressions.last)
    end

    def transform(node : ModuleDef | ClassDef | Macro)
      transform(node.body)
    end

    def transform(node : Def)
      if last_default_value = node.args.last?.try &.default_value
        transform(last_default_value)
      else
        transform(node.body)
      end
    end

    def transform(node : FunDef)
      (body = node.body) ? transform(body) : node
    end

    def transform(node : EnumDef)
      (last_member = node.members.last?) ? transform(last_member) : node
    end

    def transform(node : NamedTupleLiteral)
      (last_elem = node.entries.last?) ? transform(last_elem.value) : node
    end

    def transform(node : ArrayLiteral | TupleLiteral)
      (last_elem = node.elements.last?) ? transform(last_elem) : node
    end

    def transform(node : Assign | TypeDeclaration)
      (value = node.value) ? transform(value) : node
    end

    def transform(node : Call)
      if block = node.block
        transform(block.body)
      else
        (last_arg = node.args.last?) ? transform(last_arg) : node
      end
    end

    def transform(node : While | Until)
      if !node.body.nop?
        transform(node.body)
      else
        transform(node.cond)
      end
    end

    def transform(node : If | Unless)
      if !node.else.nop?
        transform(node.else)
      elsif !node.then.nop?
        transform(node.then)
      else
        transform(node.cond)
      end
    end

    def transform(node : ExceptionHandler)
      if ensure_ = node.ensure
        transform(ensure_)
      else
        (last_rescue = node.rescues.try &.last?) ? transform(last_rescue.body) : node
      end
    end

    def transform(node : VisibilityModifier)
      transform(node.exp)
    end

    def transform(node : Case)
      if else_ = node.else
        transform(else_)
      else
        if last_when = node.whens.try &.last?
          if !last_when.body.nop?
            transform(last_when.body)
          else
            (last_cond = last_when.conds.last?) ? transform(last_cond) : node
          end
        else
          (cond = node.cond) ? transform(cond) : node
        end
      end
    end

    def transform(node : RangeLiteral)
      transform(node.to)
    end

    def transform(node : StringInterpolation)
      transform(node.expressions.last)
    end
  end
end
