import groovy.yaml.YamlSlurper


/**
 * Parse default options from a subworkflow meta.yml file
 * @param metaFilePath Path to the meta.yml file
 * @return Map containing default option values extracted from the options input definition
 */
def parseDefaultsFromMeta(String metaFilePath) {
    def metaFile = new File(metaFilePath)
    if (!metaFile.exists()) {
        log.error "Meta file not found: ${metaFilePath}"
        return [:]
    }

    def yaml = new YamlSlurper().parse(metaFile)
    def defaults = [:]

    // Extract defaults from the 'options' input definition in meta.yml
    if (yaml.input) {
        yaml.input.each { inputDef ->
            // Look for the 'options' input which contains the default values
            if (inputDef.containsKey('options')) {
                def optionsInput = inputDef.options

                // The 'default' field contains the default values as a map
                if (optionsInput.containsKey('default')) {
                    def defaultValue = optionsInput.default

                    // If default is a Map, use it directly
                    if (defaultValue instanceof Map) {
                        defaults = defaultValue
                    } else if (defaultValue == null || defaultValue == [:] || defaultValue.toString() == '{}') {
                        // If default is empty, try to extract from description
                        log.warn "No default values found in meta.yml 'default' field"
                    }
                }
            }
        }
    }

    if (defaults.isEmpty()) {
        log.warn "Could not find default values in meta.yml file: ${metaFilePath}"
    }

    return defaults
}

/**
 * Merge provided options with defaults from meta.yml
 * @param provided Map of provided options
 * @param defaults Map of default options
 * @param strict If true, only allow keys that exist in defaults
 * @return Map containing merged options with defaults filled in
 */
def mergeWithDefaults(Map provided, Map defaults, boolean strict = false) {
    // Create a new map and populate with defaults
    def merged = new HashMap()
    if (defaults) {
        merged.putAll(defaults)
    }

    if (strict) {
        // Only allow options that exist in defaults
        provided.each { key, value ->
            if (defaults.containsKey(key)) {
                merged[key] = value
            } else {
                log.warn "Unknown option '${key}' will be ignored (not in defaults)"
            }
        }
    } else {
        // Allow all provided options
        if (provided) {
            merged.putAll(provided)
        }
    }

    return merged
}

/**
 * Convenience function to merge options with defaults from meta.yml
 * @param options Map of provided options
 * @param metaPath Path to the meta.yml file (can use ${moduleDir}/meta.yml)
 * @return Map containing merged options with defaults filled in
 */
def getOptionsWithDefaults(Map options, String metaPath) {
    def defaults = parseDefaultsFromMeta(metaPath)
    return mergeWithDefaults(options, defaults, false)
}


workflow UTILS_OPTIONS {

    take:
        ch_meta_file    // channel: [ path(meta.yml) ]
        ch_options      // channel: [ val(meta), val(options) ]

    main:
        ch_versions = channel.empty()

        // Parse defaults and merge with provided options
        ch_merged_options = ch_meta_file
            .combine(ch_options)
            .map { meta_file, _meta, provided_options ->
                def defaults = parseDefaultsFromMeta(meta_file.toString())
                def merged = mergeWithDefaults(provided_options, defaults, false)
                merged
            }

    emit:
        options = ch_merged_options      // channel: [ val(merged_options) ]
        versions = ch_versions           // channel: [ versions.yml ]
}
