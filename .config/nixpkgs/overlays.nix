[
  (final: prev: {
    inkscape-with-extensions = prev.inskcape-with-extensions.override
      {
        inkscapeExtensions = [
          prev.inkscape-extensions.textext
        ];
      };
  }
  )
]
