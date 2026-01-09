include { REGISTRATION_ANTS as REGISTER_ATLAS_REF } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_ATLAS_BUNDLES } from '../../../modules/nf-neuro/registration/antsapplytransforms/main.nf'
include { STATS_METRICSINROI     } from '../../../modules/nf-neuro/stats/metricsinroi/main'
include { ATLAS_IIT              } from '../../nf-neuro/atlas_iit/main'

workflow ATLAS_ROIMETRICS {
    take:
    ch_subject_reference  // channel : [required] meta, subject_ref_image
    ch_metrics            // channel : [required] meta, [metrics]
    options               // channel : [optional] map of options

    main:
    ch_versions = channel.empty()
    ch_bundle_masks = channel.empty()
    ch_template_ref = channel.empty()

    assert [options.use_atlas_iit].count(true) <= 1 :
        "Only one atlas can be selected at a time for ROI metrics extraction." +
        " Please set only one of the options 'use_atlas_*' to 'true'."

    if (options.use_atlas_iit) {
        ATLAS_IIT()
        ch_versions = ch_versions.mix(ATLAS_IIT.out.versions)
        ch_bundle_masks = ATLAS_IIT.out.bundle_masks.toList()
        ch_template_ref = ATLAS_IIT.out.b0
    }
    else {
        error "No atlas selected for ROI metrics extraction. " +
            "Please set one of the options 'use_atlas_*' to 'true' to run atlas-based ROI metrics."
    }

    // Register atlas reference image to subject space
    ch_input_register_atlas = ch_subject_reference
        .combine(ch_template_ref)
        .map{ meta, subject_ref, template_ref -> [meta, subject_ref, template_ref, []] }
    REGISTER_ATLAS_REF(ch_input_register_atlas)
    ch_versions = ch_versions.mix(REGISTER_ATLAS_REF.out.versions)

    // Apply the transformation to subject space to the bundles
    ch_atlas_transform_bundles = ch_subject_reference
        .join(REGISTER_ATLAS_REF.out.forward_image_transform)
        .combine(ch_bundle_masks)
        .map {
            meta, subject_ref, transform, bundles ->
                [meta, bundles, subject_ref, transform]
        }
    TRANSFORM_ATLAS_BUNDLES(ch_atlas_transform_bundles)
    ch_versions = ch_versions.mix(TRANSFORM_ATLAS_BUNDLES.out.versions)

    //
    // EXTRACT ROI VOLUME STATISTICS
    //
    // Input: [meta, [metrics_list], [masks]]
    ch_input_metricsinroi = ch_metrics
        .join(TRANSFORM_ATLAS_BUNDLES.out.warped_image)
        .map {
            meta, metrics, masks ->
                [meta, metrics, masks, []]
        }

    STATS_METRICSINROI(ch_input_metricsinroi)
    ch_versions = ch_versions.mix(STATS_METRICSINROI.out.versions)

    emit:
    stats_json        = STATS_METRICSINROI.out.stats_json
    stats_tab_mean    = STATS_METRICSINROI.out.stats_mean
    stats_tab_std     = STATS_METRICSINROI.out.stats_std

    versions        = ch_versions
}
