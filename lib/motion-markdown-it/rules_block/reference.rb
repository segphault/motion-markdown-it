module MarkdownIt
  module RulesBlock
    class Reference
      extend Common::Utils

      #------------------------------------------------------------------------------
      def self.reference(state, startLine, _endLine, silent)
        lines    = 0
        pos      = state.bMarks[startLine] + state.tShift[startLine]
        max      = state.eMarks[startLine]
        nextLine = startLine + 1

         # if it's indented more than 3 spaces, it should be a code block
        return false if state.sCount[startLine] - state.blkIndent >= 4

        return false if state.src.charCodeAt(pos) != 0x5B # [

        # Simple check to quickly interrupt scan on [link](url) at the start of line.
        # Can be useful on practice: https://github.com/markdown-it/markdown-it/issues/54
        pos += 1
        while (pos < max)
          if (state.src.charCodeAt(pos) == 0x5D &&    # ]
              state.src.charCodeAt(pos - 1) != 0x5C)  # \
            return false if (pos + 1 === max)
            return false if (state.src.charCodeAt(pos + 1) != 0x3A)  # :
            break
          end
          pos += 1
        end

        endLine = state.lineMax

        # jump line-by-line until empty one or EOF
        terminatorRules   = state.md.block.ruler.getRules('reference')

        oldParentType     = state.parentType
        state.parentType  = 'reference'

        while nextLine < endLine && !state.isEmpty(nextLine)
          # this would be a code block normally, but after paragraph
          # it's considered a lazy continuation regardless of what's there
          (nextLine += 1) and next if (state.sCount[nextLine] - state.blkIndent > 3)

          # quirk for blockquotes, this line should already be checked by that rule
          (nextLine += 1) and next if state.sCount[nextLine] < 0

          # Some tags can terminate paragraph without empty line.
          terminate = false
          (0...terminatorRules.length).each do |i|
            if (terminatorRules[i].call(state, nextLine, endLine, true))
              terminate = true
              break
            end
          end
          break if (terminate)
          nextLine += 1
        end

        str      = state.getLines(startLine, nextLine, state.blkIndent, false).strip
        max      = str.length
        labelEnd = -1

        pos = 1
        while pos < max
          ch = str.charCodeAt(pos)
          if (ch == 0x5B ) # [
            return false
          elsif (ch == 0x5D) # ]
            labelEnd = pos
            break
          elsif (ch == 0x0A) # \n
            lines += 1
          elsif (ch == 0x5C) # \
            pos += 1
            if (pos < max && str.charCodeAt(pos) == 0x0A)
              lines += 1
            end
          end
          pos += 1
        end

        return false if (labelEnd < 0 || str.charCodeAt(labelEnd + 1) != 0x3A) # :

        # [label]:   destination   'title'
        #         ^^^ skip optional whitespace here
        pos = labelEnd + 2
        while pos < max
          ch = str.charCodeAt(pos)
          if (ch == 0x0A)
            lines += 1
          elsif isSpace(ch)
          else
            break
          end
          pos += 1
        end

        # [label]:   destination   'title'
        #            ^^^^^^^^^^^ parse this
        res = state.md.helpers.parseLinkDestination(str, pos, max)
        return false if (!res[:ok])

        href = state.md.normalizeLink.call(res[:str])
        return false if (!state.md.validateLink.call(href))

        pos    = res[:pos]
        lines += res[:lines]

        # save cursor state, we could require to rollback later
        destEndPos    = pos
        destEndLineNo = lines

        # [label]:   destination   'title'
        #                       ^^^ skipping those spaces
        start = pos
        while (pos < max)
          ch = str.charCodeAt(pos)
          if (ch == 0x0A)
            lines += 1
          elsif isSpace(ch)
          else
            break
          end
          pos += 1
        end

        # [label]:   destination   'title'
        #                          ^^^^^^^ parse this
        res = state.md.helpers.parseLinkTitle(str, pos, max)
        if (pos < max && start != pos && res[:ok])
          title  = res[:str]
          pos    = res[:pos]
          lines += res[:lines]
        else
          title = ''
          pos   = destEndPos
          lines = destEndLineNo
        end

        # skip trailing spaces until the rest of the line
        while pos < max
          ch = str.charCodeAt(pos)
          break if !isSpace(ch)
          pos += 1
        end

        if (pos < max && str.charCodeAt(pos) != 0x0A)
          if (title)
            # garbage at the end of the line after title,
            # but it could still be a valid reference if we roll back
            title = ''
            pos = destEndPos
            lines = destEndLineNo
            while pos < max
              ch = str.charCodeAt(pos)
              break if !isSpace(ch)
              pos += 1
            end
          end
        end

        if (pos < max && str.charCodeAt(pos) != 0x0A)
          # garbage at the end of the line
          return false
        end

        label = normalizeReference(str.slice(1...labelEnd))
        if label == ''
          # CommonMark 0.20 disallows empty labels
          return false
        end

        # Reference can not terminate anything. This check is for safety only.
        # istanbul ignore if
        return true if (silent)

        if (state.env[:references].nil?)
          state.env[:references] = {}
        end
        if state.env[:references][label].nil?
          state.env[:references][label] = { title: title, href: href }
        end

        state.parentType = oldParentType

        state.line = startLine + lines + 1
        return true
      end

    end
  end
end
