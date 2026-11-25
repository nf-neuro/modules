include { REGISTRATION_ANTS as REGISTER_IIT_REF } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_IIT_BUNDLES } from '../../../modules/nf-neuro/registration/antsapplytransforms/main.nf'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_IIT_GM_ATLAS } from '../../../modules/nf-neuro/registration/antsapplytransforms/main.nf'
include { STATS_METRICSINROI as STATS_MASK_METRICS } from '../../../modules/nf-neuro/stats/metricsinroi/main'
include { STATS_METRICSINROI as STATS_LABELMAP_METRICS } from '../../../modules/nf-neuro/stats/metricsinroi/main'
include { STATS_ROIVOLUMES as STATS_MASK_VOLUMES } from '../../../modules/nf-neuro/stats/roivolumes/main'
include { STATS_ROIVOLUMES as STATS_LABELMAP_VOLUMES } from '../../../modules/nf-neuro/stats/roivolumes/main'
include { ATLAS_IIT              } from '../../nf-neuro/atlas_iit/main'
include { UTILS_OPTIONS } from '../utils_options/main'

workflow ATLAS_ROIMETRICS {
    take:
        ch_subject_reference  // channel : [required] meta, subject_ref_image
        ch_metrics            // channel : [required] meta, [metrics]
        ch_registered_atlas   // channel : [optional] meta, [rois], labelmap, labelmap_lut
        options               // channel : [optional] map of options

    main:
        ch_versions = channel.empty()

        UTILS_OPTIONS("${moduleDir}/meta.yml", options, true)
        options = UTILS_OPTIONS.out.options.value

        assert [options.use_atlas_iit, options.use_registered_atlas].count(true) <= 1 :
            "Only one atlas source can be selected at a time for ROI metrics extraction." +
            " Please set only one of the options 'use_atlas_*' or 'use_registered_atlas' to 'true'."

        // What the ROIs look like, and what to compute on them. The two axes are
        // independent: any combination of sources and outputs is valid.
        def roi_sources = options.roi_sources instanceof List ? options.roi_sources : [options.roi_sources]
        def roi_outputs = options.roi_outputs instanceof List ? options.roi_outputs : [options.roi_outputs]

        assert roi_sources && roi_sources.every { it in ["masks", "labelmap"] } :
            "Option 'roi_sources' must be a non-empty list holding 'masks', 'labelmap' or both," +
            " but got '${options.roi_sources}'."
        assert roi_outputs && roi_outputs.every { it in ["metrics", "volumes"] } :
            "Option 'roi_outputs' must be a non-empty list holding 'metrics', 'volumes' or both," +
            " but got '${options.roi_outputs}'."

        def want_masks    = "masks" in roi_sources
        def want_labelmap = "labelmap" in roi_sources
        def want_metrics  = "metrics" in roi_outputs
        def want_volumes  = "volumes" in roi_outputs

        // ROIs in the subject's own space, whatever their provenance. Both branches below
        // must populate these before the statistics section runs.
        ch_masks_subject_space = channel.empty()  // [meta, [masks]]
        ch_labelmap_with_lut   = channel.empty()  // [meta, labelmap, lut]

        if (options.use_atlas_iit) {
            ATLAS_IIT(
                [
                    threshold_bundles: options.use_binary_masks,
                    atlas_iit_b0: options.atlas_iit_b0,
                    atlas_iit_bundle_masks_dir: options.atlas_iit_bundle_masks_dir,
                    fetch_gm_desikan: want_labelmap,
                    atlas_iit_gm_atlas: options.atlas_iit_gm_atlas,
                    atlas_iit_gm_lut: options.atlas_iit_gm_lut
                ]
            )
            ch_versions = ch_versions.mix(ATLAS_IIT.out.versions)

            // Register the atlas reference image to subject space. Both transforms below
            // reuse this single registration.
            ch_input_register_atlas = ch_subject_reference
                .combine(ATLAS_IIT.out.b0)
                .map{ meta, subject_ref, template_ref -> [meta, subject_ref, template_ref, [], []] }
            REGISTER_IIT_REF(ch_input_register_atlas)
            ch_versions = ch_versions.mix(REGISTER_IIT_REF.out.versions)

            if (want_masks) {
                // Apply the transformation to subject space to the bundle masks
                ch_atlas_transform_bundles = ch_subject_reference
                    .join(REGISTER_IIT_REF.out.forward_image_transform)
                    .combine(ATLAS_IIT.out.bundles.toList())
                    .map {
                        meta, subject_ref, transform, bundles ->
                            [meta, bundles, subject_ref, transform]
                    }
                TRANSFORM_IIT_BUNDLES(ch_atlas_transform_bundles)
                ch_versions = ch_versions.mix(TRANSFORM_IIT_BUNDLES.out.versions)

                ch_masks_subject_space = TRANSFORM_IIT_BUNDLES.out.warped_image
            }

            if (want_labelmap) {
                ch_transform_gm = ch_subject_reference
                    .join(REGISTER_IIT_REF.out.forward_image_transform)
                    .combine(ATLAS_IIT.out.gm_atlas)
                    .map { meta, subject_ref, transform, gm_atlas ->
                        [meta, gm_atlas, subject_ref, transform]
                    }
                TRANSFORM_IIT_GM_ATLAS(ch_transform_gm)
                ch_versions = ch_versions.mix(TRANSFORM_IIT_GM_ATLAS.out.versions)

                ch_labelmap_with_lut = TRANSFORM_IIT_GM_ATLAS.out.warped_image
                    .combine(ATLAS_IIT.out.gm_lut)
            }
        }
        else if (options.use_registered_atlas) {
            // The caller registered the atlas itself, so no download and no registration
            // happen here. Entries are already in each subject's space.
            if (want_masks) {
                ch_masks_subject_space = ch_registered_atlas
                    .map { meta, masks, _labelmap, _lut -> [meta, masks] }
                    .filter { _meta, masks -> masks }
            }

            if (want_labelmap) {
                ch_labelmap_with_lut = ch_registered_atlas
                    .filter { _meta, _masks, labelmap, lut -> labelmap && lut }
                    .map { meta, _masks, labelmap, lut -> [meta, labelmap, lut] }
            }
        }
        else {
            error "No atlas selected for ROI metrics extraction. " +
                "Please set one of the options 'use_atlas_*' to 'true' to run atlas-based ROI metrics, " +
                "or set 'use_registered_atlas' to 'true' and supply the atlas through 'ch_registered_atlas'."
        }

        //
        // STATISTICS OVER INDIVIDUAL ROI MASKS ('masks' source)
        //
        ch_mask_stats_json = channel.empty()
        ch_mask_stats_mean = channel.empty()
        ch_mask_stats_std  = channel.empty()
        ch_mask_volumes    = channel.empty()

        if (want_masks && want_metrics) {
            // Input: [meta, [metrics_list], [masks]]
            ch_input_mask_metrics = ch_metrics
                .join(ch_masks_subject_space)
                .map {
                    meta, metrics, masks ->
                        [meta, metrics, masks, []]
                }

            STATS_MASK_METRICS(ch_input_mask_metrics)
            ch_versions = ch_versions.mix(STATS_MASK_METRICS.out.versions)

            ch_mask_stats_json = STATS_MASK_METRICS.out.stats_json
            ch_mask_stats_mean = STATS_MASK_METRICS.out.stats_mean
            ch_mask_stats_std  = STATS_MASK_METRICS.out.stats_std
        }

        if (want_masks && want_volumes) {
            ch_mask_volumes_input = ch_masks_subject_space
                .map { meta, masks -> [meta, masks, []] }
            STATS_MASK_VOLUMES(ch_mask_volumes_input)
            ch_versions = ch_versions.mix(STATS_MASK_VOLUMES.out.versions)
            ch_mask_volumes = STATS_MASK_VOLUMES.out.volumes
        }

        //
        // STATISTICS OVER A LABELMAP ('labelmap' source) — the IIT GM Desikan
        // parcellation under 'use_atlas_iit', or whatever labelmap the caller
        // supplied through 'ch_registered_atlas'.
        //
        ch_labelmap_stats_json = channel.empty()
        ch_labelmap_stats_mean = channel.empty()
        ch_labelmap_stats_std  = channel.empty()
        ch_labelmap_volumes    = channel.empty()

        if (want_labelmap && want_metrics) {
            ch_input_labelmap_metrics = ch_metrics
                .join(ch_labelmap_with_lut)
                .map { meta, metrics, labelmap, lut -> [meta, metrics, labelmap, lut] }

            STATS_LABELMAP_METRICS(ch_input_labelmap_metrics)
            ch_versions = ch_versions.mix(STATS_LABELMAP_METRICS.out.versions)

            ch_labelmap_stats_json = STATS_LABELMAP_METRICS.out.stats_json
            ch_labelmap_stats_mean = STATS_LABELMAP_METRICS.out.stats_mean
            ch_labelmap_stats_std  = STATS_LABELMAP_METRICS.out.stats_std
        }

        if (want_labelmap && want_volumes) {
            STATS_LABELMAP_VOLUMES(ch_labelmap_with_lut)
            ch_versions = ch_versions.mix(STATS_LABELMAP_VOLUMES.out.versions)
            ch_labelmap_volumes = STATS_LABELMAP_VOLUMES.out.volumes
        }

    emit:
        mask_stats_json         = ch_mask_stats_json
        mask_stats_tab_mean     = ch_mask_stats_mean
        mask_stats_tab_std      = ch_mask_stats_std
        mask_volumes            = ch_mask_volumes

        labelmap_stats_json     = ch_labelmap_stats_json
        labelmap_stats_tab_mean = ch_labelmap_stats_mean
        labelmap_stats_tab_std  = ch_labelmap_stats_std
        labelmap_volumes        = ch_labelmap_volumes

        versions                = ch_versions
}
